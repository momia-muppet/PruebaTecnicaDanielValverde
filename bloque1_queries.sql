/* ============================================================================
   BLOQUE 1 — SQL AVANZADO
   Dialecto: SQL estándar / BigQuery Standard SQL.
   Nota: Query 2 usa PERCENTILE_CONT(...) WITHIN GROUP (sintaxis ANSI/BigQuery).
   Los supuestos de negocio, decisiones y prompts de IA usados para cada query
   están documentados en el README.md principal, no aquí, para mantener este
   archivo enfocado en el código. Cada CTE trae un comentario /* ... *­/ corto
   explicando qué hace y, cuando aplica, por qué está estructurado así.
   ============================================================================ */


/* ============================================================================
   QUERY 1 — Ventas Comparables (Comp Sales)
   ============================================================================ */

/* date_bounds: calcula el año calendario de la última fecha con datos
   (MAX(transaction_date)), sin fechas hardcodeadas — si se carga más
   historia, la query recalcula sola los periodos a comparar. */
WITH date_bounds AS (
    SELECT
        DATE_TRUNC('year', MAX(transaction_date)) AS current_period_start,
        MAX(transaction_date)                     AS current_period_end
    FROM transactions
),

/* period_defs: a partir de date_bounds, deriva el periodo anterior (mismo
   rango -1 año) y el corte de elegibilidad de tienda (13 meses antes del
   inicio del periodo actual), todo con aritmética de INTERVAL. */
period_defs AS (
    SELECT
        current_period_start,
        current_period_end,
        current_period_start - INTERVAL '1' YEAR   AS prior_period_start,
        current_period_end   - INTERVAL '1' YEAR   AS prior_period_end,
        current_period_start - INTERVAL '13' MONTH AS eligibility_cutoff
    FROM date_bounds
),

/* eligible_stores: filtra tiendas con >= 13 meses de operación. Usamos
   CROSS JOIN porque period_defs es una sola fila de constantes de fecha;
   el cross join simplemente "pega" esas constantes a cada fila de stores
   para poder filtrar y usarlas más abajo sin subqueries repetidas. */
eligible_stores AS (
    SELECT s.store_id, s.country, s.format, pd.*
    FROM stores s
    CROSS JOIN period_defs pd
    WHERE s.opening_date <= pd.eligibility_cutoff
),

/* net_sales: GMV neto (COMPLETED - RETURNED) por tienda, clasificado en
   'ACTUAL' o 'ANTERIOR' según en qué rango cae la fecha de la transacción.
   El INNER JOIN contra eligible_stores ya descarta las tiendas no elegibles
   antes de agregar. */
net_sales AS (
    SELECT
        t.store_id,
        CASE
            WHEN t.transaction_date BETWEEN es.current_period_start AND es.current_period_end THEN 'ACTUAL'
            WHEN t.transaction_date BETWEEN es.prior_period_start AND es.prior_period_end THEN 'ANTERIOR'
        END AS periodo,
        SUM(CASE WHEN t.status = 'COMPLETED' THEN t.total_amount ELSE -t.total_amount END) AS gmv_neto
    FROM transactions t
    INNER JOIN eligible_stores es ON t.store_id = es.store_id
    WHERE t.transaction_date BETWEEN es.prior_period_start AND es.current_period_end
    GROUP BY 1, 2
    HAVING periodo IS NOT NULL
),

/* store_comp: pivotea net_sales para tener una sola fila por tienda con
   gmv_actual y gmv_anterior lado a lado (necesario para calcular el % de
   crecimiento en la siguiente capa). */
store_comp AS (
    SELECT
        es.store_id, es.country, es.format,
        COALESCE(MAX(CASE WHEN ns.periodo = 'ACTUAL'   THEN ns.gmv_neto END), 0) AS gmv_actual,
        COALESCE(MAX(CASE WHEN ns.periodo = 'ANTERIOR' THEN ns.gmv_neto END), 0) AS gmv_anterior
    FROM eligible_stores es
    LEFT JOIN net_sales ns ON es.store_id = ns.store_id
    GROUP BY 1, 2, 3
)

/* 1a) Detalle por tienda + ranking dentro de su formato (RANK() con ORDER BY
   el % de crecimiento calculado inline, para no materializar otra columna). */
SELECT
    store_id, country, format,
    ROUND(gmv_anterior, 2) AS gmv_anterior,
    ROUND(gmv_actual, 2)   AS gmv_actual,
    ROUND(100.0 * (gmv_actual - gmv_anterior) / NULLIF(gmv_anterior, 0), 2) AS comp_sales_growth_pct,
    RANK() OVER (
        PARTITION BY format
        ORDER BY (gmv_actual - gmv_anterior) / NULLIF(gmv_anterior, 0) DESC
    ) AS ranking_en_formato
FROM store_comp
ORDER BY format, ranking_en_formato;


/* 1b) Mismo cálculo pero agregado por país y formato en vez de por tienda. */
WITH date_bounds AS (
    SELECT
        DATE_TRUNC('year', MAX(transaction_date)) AS current_period_start,
        MAX(transaction_date)                     AS current_period_end
    FROM transactions
),
period_defs AS (
    SELECT
        current_period_start, current_period_end,
        current_period_start - INTERVAL '1' YEAR   AS prior_period_start,
        current_period_end   - INTERVAL '1' YEAR   AS prior_period_end,
        current_period_start - INTERVAL '13' MONTH AS eligibility_cutoff
    FROM date_bounds
),
eligible_stores AS (
    SELECT s.store_id, s.country, s.format, pd.*
    FROM stores s
    CROSS JOIN period_defs pd
    WHERE s.opening_date <= pd.eligibility_cutoff
),
net_sales AS (
    SELECT
        t.store_id,
        CASE
            WHEN t.transaction_date BETWEEN es.current_period_start AND es.current_period_end THEN 'ACTUAL'
            WHEN t.transaction_date BETWEEN es.prior_period_start AND es.prior_period_end THEN 'ANTERIOR'
        END AS periodo,
        SUM(CASE WHEN t.status = 'COMPLETED' THEN t.total_amount ELSE -t.total_amount END) AS gmv_neto
    FROM transactions t
    INNER JOIN eligible_stores es ON t.store_id = es.store_id
    WHERE t.transaction_date BETWEEN es.prior_period_start AND es.current_period_end
    GROUP BY 1, 2
    HAVING periodo IS NOT NULL
)
SELECT
    es.country, es.format,
    COUNT(DISTINCT es.store_id) AS num_tiendas_comp,
    ROUND(SUM(CASE WHEN ns.periodo = 'ANTERIOR' THEN ns.gmv_neto ELSE 0 END), 2) AS gmv_anterior,
    ROUND(SUM(CASE WHEN ns.periodo = 'ACTUAL'   THEN ns.gmv_neto ELSE 0 END), 2) AS gmv_actual,
    ROUND(
        100.0 * (
            SUM(CASE WHEN ns.periodo = 'ACTUAL'   THEN ns.gmv_neto ELSE 0 END) -
            SUM(CASE WHEN ns.periodo = 'ANTERIOR' THEN ns.gmv_neto ELSE 0 END)
        ) / NULLIF(SUM(CASE WHEN ns.periodo = 'ANTERIOR' THEN ns.gmv_neto ELSE 0 END), 0)
    , 2) AS comp_sales_growth_pct
FROM eligible_stores es
LEFT JOIN net_sales ns ON es.store_id = ns.store_id
GROUP BY 1, 2
ORDER BY 1, 2;


/* ============================================================================
   QUERY 2 — Productividad por Metro Cuadrado
   ============================================================================ */

/* date_bounds: trimestre calendario de la última fecha con datos, calculado
   con DATE_TRUNC('quarter', ...), no hardcodeado. */
WITH date_bounds AS (
    SELECT DATE_TRUNC('quarter', MAX(transaction_date)) AS q_start,
           MAX(transaction_date) AS q_end
    FROM transactions
),

/* store_quarter: GMV neto, conteo de transacciones (solo COMPLETED) y ticket
   promedio del trimestre por tienda. CROSS JOIN con date_bounds por el mismo
   motivo que en Query 1: pegar las 2 fechas constantes a cada fila para
   poder filtrar transactions dentro del WHERE. */
store_quarter AS (
    SELECT
        t.store_id,
        SUM(CASE WHEN t.status = 'COMPLETED' THEN t.total_amount ELSE -t.total_amount END) AS gmv_neto,
        COUNT(DISTINCT CASE WHEN t.status = 'COMPLETED' THEN t.transaction_id END) AS num_transacciones,
        AVG(CASE WHEN t.status = 'COMPLETED' AND t.total_amount > 0 THEN t.total_amount END) AS ticket_promedio
    FROM transactions t
    CROSS JOIN date_bounds db
    WHERE t.transaction_date BETWEEN db.q_start AND db.q_end
    GROUP BY 1
),

/* store_metrics: LEFT JOIN contra stores (no INNER) para que ninguna tienda
   desaparezca del reporte aunque no haya vendido nada en el trimestre;
   COALESCE a 0 cubre ese caso al dividir por size_sqm. */
store_metrics AS (
    SELECT
        s.store_id, s.country, s.format, s.size_sqm,
        COALESCE(sq.gmv_neto, 0) AS gmv_trimestre,
        COALESCE(sq.num_transacciones, 0) AS num_transacciones,
        sq.ticket_promedio,
        COALESCE(sq.gmv_neto, 0) / s.size_sqm AS gmv_por_m2,
        COALESCE(sq.num_transacciones, 0) / s.size_sqm AS transacciones_por_m2
    FROM stores s
    LEFT JOIN store_quarter sq ON s.store_id = sq.store_id
)

/* Capa final: ranking y flag de bajo rendimiento usando window functions
   (RANK y PERCENTILE_CONT) particionadas por formato, en una sola pasada. */
SELECT
    store_id, country, format, size_sqm,
    ROUND(gmv_trimestre, 2) AS gmv_trimestre,
    ROUND(gmv_por_m2, 2) AS gmv_por_m2,
    ROUND(transacciones_por_m2, 4) AS transacciones_por_m2,
    ROUND(ticket_promedio, 2) AS ticket_promedio,
    RANK() OVER (PARTITION BY format ORDER BY gmv_por_m2 DESC) AS ranking_en_formato,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY gmv_por_m2) OVER (PARTITION BY format), 2) AS p25_gmv_m2_formato,
    CASE WHEN gmv_por_m2 < PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY gmv_por_m2) OVER (PARTITION BY format)
         THEN 'BAJO_RENDIMIENTO' ELSE 'OK' END AS flag_rendimiento
FROM store_metrics
ORDER BY format, ranking_en_formato;


/* ============================================================================
   QUERY 3 — Cohortes de Clientes con Tarjeta de Lealtad
   ============================================================================ */

/* loyalty_tx: universo base, solo clientes identificados (loyalty_card=TRUE)
   con transacciones completadas, truncadas a mes. */
WITH loyalty_tx AS (
    SELECT customer_id, transaction_id, total_amount,
           DATE_TRUNC('month', transaction_date) AS tx_month
    FROM transactions
    WHERE loyalty_card = TRUE AND status = 'COMPLETED'
),

/* customer_cohort: primer mes de compra de cada cliente = su cohorte. */
customer_cohort AS (
    SELECT customer_id, MIN(tx_month) AS cohort_month
    FROM loyalty_tx
    GROUP BY 1
),

/* activity: une cada transacción con la cohorte de su cliente y calcula
   month_index = cuántos meses pasaron desde la cohorte (DATE_DIFF). */
activity AS (
    SELECT lt.customer_id, cc.cohort_month, lt.total_amount,
           DATE_DIFF('month', cc.cohort_month, lt.tx_month) AS month_index
    FROM loyalty_tx lt
    JOIN customer_cohort cc ON lt.customer_id = cc.customer_id
),

/* cohort_sizes: tamaño de cada cohorte (denominador de la retención). */
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM customer_cohort GROUP BY 1
),

/* retention: clientes activos y ticket promedio en los meses de interés
   (0, 1, 2, 3, 6). Se filtra a esos meses aquí para no agregar de más. */
retention AS (
    SELECT cohort_month, month_index,
           COUNT(DISTINCT customer_id) AS clientes_activos,
           AVG(total_amount) AS ticket_promedio
    FROM activity
    WHERE month_index IN (0, 1, 2, 3, 6)
    GROUP BY 1, 2
)

/* Capa final: pivotea retention (filas=meses) a columnas por mes usando
   MAX(CASE...). El CASE de retencion_m6_pct devuelve NULL si la cohorte
   aún no cumple 6 meses dentro de la ventana de datos (right-censoring). */
SELECT
    cs.cohort_month,
    cs.cohort_size,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN r.month_index = 1 THEN r.clientes_activos END), 0) / cs.cohort_size, 1) AS retencion_m1_pct,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN r.month_index = 2 THEN r.clientes_activos END), 0) / cs.cohort_size, 1) AS retencion_m2_pct,
    ROUND(100.0 * COALESCE(MAX(CASE WHEN r.month_index = 3 THEN r.clientes_activos END), 0) / cs.cohort_size, 1) AS retencion_m3_pct,
    CASE WHEN cs.cohort_month <= (SELECT DATE_TRUNC('month', MAX(transaction_date)) - INTERVAL '6' MONTH FROM transactions)
         THEN ROUND(100.0 * COALESCE(MAX(CASE WHEN r.month_index = 6 THEN r.clientes_activos END), 0) / cs.cohort_size, 1)
         ELSE NULL END AS retencion_m6_pct,
    ROUND(MAX(CASE WHEN r.month_index = 0 THEN r.ticket_promedio END), 2) AS ticket_m0,
    ROUND(MAX(CASE WHEN r.month_index = 1 THEN r.ticket_promedio END), 2) AS ticket_m1,
    ROUND(MAX(CASE WHEN r.month_index = 3 THEN r.ticket_promedio END), 2) AS ticket_m3,
    ROUND(MAX(CASE WHEN r.month_index = 6 THEN r.ticket_promedio END), 2) AS ticket_m6
FROM cohort_sizes cs
LEFT JOIN retention r ON cs.cohort_month = r.cohort_month
GROUP BY cs.cohort_month, cs.cohort_size
ORDER BY cs.cohort_month;


/* ============================================================================
   QUERY 4 — GMROI por Proveedor y Categoría
   ============================================================================ */

/* date_bounds: rango total de fechas del dataset, para calcular velocidad
   de venta (unidades/día) más abajo. */
WITH date_bounds AS (
    SELECT MIN(transaction_date) AS d_start, MAX(transaction_date) AS d_end
    FROM transactions
),

/* item_sales: unidades y GMV netos (COMPLETED - RETURNED) por SKU. El
   INNER JOIN contra vendors (en vez de LEFT JOIN) descarta a propósito los
   5 SKUs con vendor_id huérfano — no se puede calcular GMROI "por
   proveedor" de un proveedor que no existe en el maestro. */
item_sales AS (
    SELECT
        ti.item_id, p.vendor_id, p.category,
        SUM(CASE WHEN t.status = 'COMPLETED' THEN ti.quantity ELSE -ti.quantity END) AS unidades_netas,
        SUM(CASE WHEN t.status = 'COMPLETED' THEN ti.quantity * ti.unit_price ELSE -ti.quantity * ti.unit_price END) AS gmv_neto
    FROM transaction_items ti
    JOIN transactions t ON ti.transaction_id = t.transaction_id
    JOIN products p ON ti.item_id = p.item_id
    INNER JOIN vendors v ON p.vendor_id = v.vendor_id
    GROUP BY 1, 2, 3
),

/* vendor_category: agrega item_sales a nivel vendor+categoría; costo_total
   multiplica unidades netas por el costo unitario del producto (products.cost). */
vendor_category AS (
    SELECT
        isales.vendor_id, v.vendor_name, isales.category,
        SUM(isales.gmv_neto) AS gmv,
        SUM(isales.unidades_netas * p.cost) AS costo_total,
        COUNT(DISTINCT isales.item_id) AS skus_activos,
        SUM(isales.unidades_netas) AS unidades_totales
    FROM item_sales isales
    JOIN products p ON isales.item_id = p.item_id
    JOIN vendors v ON isales.vendor_id = v.vendor_id
    GROUP BY 1, 2, 3
)

/* Capa final: margen, GMROI y flag. CROSS JOIN con date_bounds (una sola
   fila) para tener MIN/MAX de fecha disponibles en cada fila y calcular
   velocidad_unid_dia sin subquery repetida. */
SELECT
    vc.vendor_id, vc.vendor_name, vc.category,
    ROUND(vc.gmv, 2) AS gmv,
    ROUND(vc.costo_total, 2) AS costo_total,
    ROUND(vc.gmv - vc.costo_total, 2) AS margen_bruto,
    ROUND((vc.gmv - vc.costo_total) / NULLIF(vc.costo_total, 0), 2) AS gmroi,
    vc.skus_activos,
    ROUND(vc.unidades_totales / DATE_DIFF('day', db.d_start, db.d_end), 3) AS velocidad_unid_dia,
    CASE WHEN (vc.gmv - vc.costo_total) / NULLIF(vc.costo_total, 0) < 1 THEN 'GMROI_BAJO' ELSE 'OK' END AS flag_gmroi
FROM vendor_category vc
CROSS JOIN date_bounds db
ORDER BY gmroi ASC;


/* ============================================================================
   QUERY 5 — Detección de Posibles Quiebres de Stock
   ============================================================================ */

/* daily_sales: GMV vendido por tienda-item-día (solo días con >=1 venta
   completada; los días sin fila son, por definición, días sin venta). */
WITH daily_sales AS (
    SELECT
        t.store_id, ti.item_id, t.transaction_date AS sale_date,
        SUM(ti.quantity * ti.unit_price) AS gmv_dia
    FROM transaction_items ti
    JOIN transactions t ON ti.transaction_id = t.transaction_id
    WHERE t.status = 'COMPLETED'
    GROUP BY 1, 2, 3
),

/* with_gaps: LAG(sale_date) trae la fecha de venta anterior de ese mismo
   item en esa misma tienda, para poder medir la distancia entre ventas
   consecutivas. avg_gmv_dia_previo es una media móvil (solo filas
   anteriores, ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) que sirve
   de base para estimar el GMV perdido durante el gap sin usar datos futuros. */
with_gaps AS (
    SELECT
        store_id, item_id, sale_date, gmv_dia,
        LAG(sale_date) OVER w AS prev_sale_date,
        AVG(gmv_dia) OVER (PARTITION BY store_id, item_id ORDER BY sale_date
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS avg_gmv_dia_previo
    FROM daily_sales
    WINDOW w AS (PARTITION BY store_id, item_id ORDER BY sale_date)
),

/* gaps_raw: convierte cada par de ventas consecutivas en un "gap" con su
   duración en días (DATE_DIFF - 1, porque el día de la venta anterior y el
   de la siguiente no cuentan como días sin venta). */
gaps_raw AS (
    SELECT
        store_id, item_id, prev_sale_date AS gap_start, sale_date AS gap_end,
        DATE_DIFF('day', prev_sale_date, sale_date) - 1 AS duracion_dias,
        avg_gmv_dia_previo
    FROM with_gaps
    WHERE prev_sale_date IS NOT NULL
),

/* gaps_with_baseline: calcula la cadencia histórica de gaps anteriores de
   ese mismo item-tienda (media móvil de duracion_dias), para poder
   distinguir un gap "anómalo" de uno rutinario en la capa final. */
gaps_with_baseline AS (
    SELECT *,
        AVG(duracion_dias) OVER (PARTITION BY store_id, item_id ORDER BY gap_start
                                  ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cadencia_historica_dias
    FROM gaps_raw
)

/* Capa final: filtra gaps >= 3 días (definición del enunciado) y agrega
   es_quiebre_anomalo = TRUE solo si el gap dura más del doble de la
   cadencia histórica propia del item (o si es su primer gap conocido). */
SELECT
    g.store_id, g.item_id, p.category,
    g.gap_start + INTERVAL '1' DAY AS gap_desde,
    g.gap_end - INTERVAL '1' DAY AS gap_hasta,
    g.duracion_dias,
    ROUND(g.cadencia_historica_dias, 1) AS cadencia_historica_dias,
    ROUND(g.avg_gmv_dia_previo, 2) AS gmv_diario_promedio_previo,
    ROUND(g.avg_gmv_dia_previo * g.duracion_dias, 2) AS gmv_estimado_perdido,
    CASE WHEN g.duracion_dias >= 3
              AND (g.cadencia_historica_dias IS NULL OR g.duracion_dias > 2 * g.cadencia_historica_dias)
         THEN TRUE ELSE FALSE END AS es_quiebre_anomalo
FROM gaps_with_baseline g
JOIN products p ON g.item_id = p.item_id
WHERE g.duracion_dias >= 3
ORDER BY gmv_estimado_perdido DESC;


/* ============================================================================
   QUERY 6 — Impacto de Promociones en Ticket y Volumen (Basket Uplift)
   ============================================================================ */

/* category_in_tx: por transacción y categoría, unidades compradas de esa
   categoría y si alguno de esos ítems estaba en promo (MAX de un booleano
   convertido a 1/0 = "al menos uno"). */
WITH category_in_tx AS (
    SELECT
        ti.transaction_id, p.category,
        SUM(ti.quantity) AS unidades_categoria,
        MAX(CASE WHEN ti.was_on_promo THEN 1 ELSE 0 END) AS categoria_en_promo
    FROM transaction_items ti
    JOIN products p ON ti.item_id = p.item_id
    GROUP BY 1, 2
),

/* tx_basket: tamaño total de la canasta (todas las categorías) por
   transacción, para poder separar "más unidades de lo promocionado" de
   "más unidades en general". */
tx_basket AS (
    SELECT transaction_id, SUM(quantity) AS unidades_totales_tx
    FROM transaction_items GROUP BY 1
),

/* agg: promedia ticket (total_amount de toda la transacción, no solo la
   categoría) y tamaño de canasta, agrupado por categoría y si tenía promo. */
agg AS (
    SELECT
        cit.category, cit.categoria_en_promo,
        AVG(t.total_amount) AS ticket_promedio,
        AVG(tb.unidades_totales_tx) AS unidades_promedio_canasta
    FROM category_in_tx cit
    JOIN transactions t ON cit.transaction_id = t.transaction_id
    JOIN tx_basket tb ON cit.transaction_id = tb.transaction_id
    WHERE t.status = 'COMPLETED'
    GROUP BY 1, 2
)

/* Capa final: pivotea agg (con/sin promo) a columnas lado a lado y calcula
   el % de uplift de ticket y de unidades. */
SELECT
    category,
    ROUND(MAX(CASE WHEN categoria_en_promo = 1 THEN ticket_promedio END), 2) AS ticket_con_promo,
    ROUND(MAX(CASE WHEN categoria_en_promo = 0 THEN ticket_promedio END), 2) AS ticket_sin_promo,
    ROUND(100.0 * (MAX(CASE WHEN categoria_en_promo = 1 THEN ticket_promedio END) - MAX(CASE WHEN categoria_en_promo = 0 THEN ticket_promedio END))
          / MAX(CASE WHEN categoria_en_promo = 0 THEN ticket_promedio END), 2) AS ticket_uplift_pct,
    ROUND(MAX(CASE WHEN categoria_en_promo = 1 THEN unidades_promedio_canasta END), 2) AS unidades_con_promo,
    ROUND(MAX(CASE WHEN categoria_en_promo = 0 THEN unidades_promedio_canasta END), 2) AS unidades_sin_promo,
    ROUND(100.0 * (MAX(CASE WHEN categoria_en_promo = 1 THEN unidades_promedio_canasta END) - MAX(CASE WHEN categoria_en_promo = 0 THEN unidades_promedio_canasta END))
          / MAX(CASE WHEN categoria_en_promo = 0 THEN unidades_promedio_canasta END), 2) AS unidades_uplift_pct
FROM agg
GROUP BY category
ORDER BY ticket_uplift_pct DESC;
