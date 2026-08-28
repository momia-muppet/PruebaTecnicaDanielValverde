# Bloque 2B/2C — Decisiones de Diseño, Pipeline y Gobernanza

## A. Decisiones de diseño del modelo (justificación)

**1. Cliente "Desconocido" como fila explícita en `dim_cliente`, no NULL.**
El 59.8% de las transacciones no tiene `customer_id` (bloque0_auditoria.md #1). En vez de dejar `customer_key` en NULL en `fact_venta_linea` — lo que rompe INNER JOINs y obliga a acordarse de usar LEFT JOIN en cada query — se crea una fila `customer_key = 'UNKNOWN'` en la dimensión. Todas las líneas de venta de clientes anónimos apuntan a esa fila. Los análisis a nivel cliente (cohortes, retención) simplemente filtran `WHERE customer_key != 'UNKNOWN'`; los análisis de GMV total no necesitan ningún tratamiento especial.

**2. Grano de `fact_venta_linea` = línea de producto, no cabecera de transacción.**
Se pudo modelar a nivel de transacción (una fila por venta) y guardar el detalle de producto en una tabla puente, pero eso obligaría a un JOIN adicional para cualquier análisis de producto/categoría/proveedor (que es la mayoría: GMROI, Pareto de categorías, impacto de promociones). Modelar al grano más bajo posible (línea) y dejar que todo lo demás se resuelva agregando hacia arriba es el principio estándar de Kimball, y en este caso el costo de duplicar `total_amount`, `payment_method`, `status` en cada línea es bajo comparado con el beneficio de tener un solo fact table para casi todos los casos de uso.

**3. La asignación al experimento A/B como *factless fact table* separada (`fact_asignacion_promocion`), no como columna en `dim_tienda`.**
La alternativa obvia era agregar `variant`/`promo_name` como atributos de `dim_tienda`. Se descartó por dos razones: (a) una tienda puede participar en más de un experimento a lo largo del tiempo (la relación es tienda×promoción, no 1:1 con la tienda), y (b) modelarlo como evento separado permite que una query de auditoría tan simple como `GROUP BY store_key HAVING COUNT(DISTINCT variant) > 1` detecte automáticamente el problema real que encontramos en los datos (TIENDA_008 y TIENDA_037 asignadas a ambas variantes — bloque0_auditoria.md #8). Si `variant` fuera una columna de `dim_tienda`, ese error de integridad sería mucho más difícil de detectar (la tabla solo permitiría un valor por tienda, escondiendo el conflicto en vez de exponerlo).

**4. `dim_fecha` como dimensión conformada en vez de usar `DATE` directo en cada fact table.**
Casi todas las preguntas de negocio piden agrupar por semana, trimestre o año (estacionalidad, Comp Sales, cohortes). Tener una dimensión de fecha precalculada con esas columnas evita repetir lógica de `DATE_TRUNC`/`EXTRACT` en cada query del BI y garantiza que "semana" o "trimestre" signifiquen exactamente lo mismo en todos los reportes — un requisito directo de la Parte C (gobernanza) sobre por qué dos reportes pueden mostrar números distintos.

---

## B. Diseño del pipeline ETL/ELT

**¿Cómo manejar que las tiendas reportan con hasta 2 horas de retraso?**
El pipeline no se dispara apenas termina el día calendario; corre con un colchón de tiempo después de medianoche (p. ej. 03:00 hora local) para dar margen a que los últimos POS del día terminen de sincronizar. Además, cada corrida no solo carga "el día de ayer": vuelve a procesar una ventana móvil de los últimos 3 días (lookback window). Como la carga es un MERGE idempotente por `transaction_id` (ver más abajo), reprocesar días ya cargados no duplica nada — simplemente actualiza si llegó algo nuevo o tardío.

**¿Cómo detectar automáticamente que una tienda dejó de enviar datos?**
Un job de monitoreo aparte (no el pipeline de carga en sí) compara, para cada tienda, el conteo de transacciones del día contra su propio promedio móvil de los últimos 7 días del mismo día de la semana. Si una tienda cae por debajo de un umbral (p. ej. <20% de su histórico) o no reporta absolutamente nada pasada su hora de cierre + 2h de margen, se dispara una alerta (Slack/email al equipo de operaciones de esa tienda). Esto es exactamente el chequeo de "frescura" que ya hicimos manualmente en el Bloque 0 (hallazgo del gap de 7 días en TIENDA_012) — la idea es que ese chequeo corra solo, todos los días, no una vez al hacer un análisis ad-hoc.

**¿Cómo hacer cargas incrementales sin duplicar transacciones?**
`transaction_id` es la clave natural de idempotencia. La carga usa `MERGE` (nativo en BigQuery): si el `transaction_id` ya existe en la tabla destino, actualiza (por ejemplo, si una transacción cambió de `COMPLETED` a `RETURNED`); si no existe, inserta. Esto, combinado con el lookback window de 3 días del punto anterior, permite reprocesar sin miedo a duplicar ni a perder cambios de estado tardíos.

**¿Con qué frecuencia correría el pipeline?**
Si el dashboard necesita refresh diario, una corrida diaria (03:00 hora local, con el lookback de 3 días) es suficiente y más barata que near-real-time. Si en el futuro se necesita monitoreo operativo intradía (p. ej. detectar quiebres de stock el mismo día), se puede agregar una segunda corrida liviana cada 2-4 horas que solo actualice métricas operativas críticas, sin tocar las tablas históricas completas.

---

## C. Gobernanza

**¿Cómo proteger `customer_id` para cumplir políticas de privacidad?**
El `customer_id` original no debería viajar más allá de la capa de ingesta cruda. En el modelo dimensional, `dim_cliente` expone un `customer_key` (surrogate, no reversible sin acceso a la tabla de mapeo) en vez del ID original. El mapeo `customer_id → customer_key` vive en una tabla separada con acceso restringido (column-level security / tabla cifrada, acceso solo para el equipo autorizado a hacer trazabilidad individual, p. ej. atención al cliente o cumplimiento). Los dashboards y el equipo analítico solo ven `customer_key`, suficiente para cohortes y retención sin exponer el identificador real.

**¿Quién debería ser el data owner de la tabla de transacciones?**
El equipo de **Operaciones de Tienda / Comercial** (la función de negocio que genera el dato en el POS), no el equipo de datos. El equipo de datos actúa como *data steward* (responsable de la calidad técnica, el pipeline y el modelo), pero las decisiones sobre qué significa un campo, cómo se corrige un error de captura, o si un ajuste de negocio es válido, le corresponden al dueño del proceso que originó el dato.

**Si dos reportes muestran GMV diferente para la misma tienda y el mismo día, ¿cuál es el proceso para resolverlo?**
1. Confirmar que ambos reportes usan la misma definición de GMV (¿neto de devoluciones o bruto? ¿incluye `status='RETURNED'`?) y el mismo *cutoff* de fecha/hora de carga — la causa más común de discrepancias no es un bug, es una definición distinta.
2. Si las definiciones coinciden, correr una query de reconciliación contra la fuente de verdad (`fact_venta_linea`, que es la tabla certificada del modelo) y comparar contra cada reporte para aislar cuál se desvía.
3. Revisar si uno de los reportes está leyendo de una copia/caché desactualizada (problema de frescura del pipeline) en vez de la tabla final.
4. Documentar la causa raíz y, si es un problema recurrente de definiciones divergentes, formalizar una métrica única certificada en un catálogo de métricas (single source of truth) para que ningún reporte nuevo pueda recalcular "GMV" a su manera.
