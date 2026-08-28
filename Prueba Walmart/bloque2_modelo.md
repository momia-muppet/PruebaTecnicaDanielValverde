# Bloque 2A — Modelo Dimensional (Star Schema)

> Diseñado para BigQuery. Soporta: Comp Sales por tienda/formato/país/período,
> GMROI por vendor/categoría/región, retención de clientes por cohorte,
> productividad de tienda y análisis de promociones (A/B test).
>
> Cómo generar el diagrama: pega el bloque DBML de más abajo en
> [dbdiagram.io](https://dbdiagram.io) → se renderiza solo → Export → PDF.
> También sirve pegado en draw.io con el plugin de importación DBML.

---

## 1. Tabla de hechos principal

### `fact_venta_linea` (grano: una fila por línea de producto vendida)

| Campo | Tipo | Descripción |
|---|---|---|
| `venta_linea_key` | STRING (PK) | = transaction_item_id original |
| `transaction_id` | STRING | Dimensión degenerada — agrupa líneas de una misma venta |
| `date_key` | DATE (FK → dim_fecha) | Fecha de la transacción |
| `store_key` | STRING (FK → dim_tienda) | |
| `item_key` | STRING (FK → dim_producto) | |
| `customer_key` | STRING (FK → dim_cliente) | `'UNKNOWN'` si no hay tarjeta de lealtad |
| `quantity` | INT | Unidades vendidas |
| `unit_price` | FLOAT | Precio al momento de la venta |
| `line_amount` | FLOAT | quantity × unit_price (calculado) |
| `was_on_promo` | BOOLEAN | |
| `status` | STRING | COMPLETED / RETURNED (degenerada) |
| `payment_method` | STRING | CASH / CARD / DIGITAL (degenerada, a nivel header) |
| `total_amount_transaccion` | FLOAT | total_amount original de la transacción (repetido en cada línea, para reconciliar contra Σ líneas — ver bloque0_auditoria hallazgo #2) |

**Grano elegido: línea de producto, no cabecera de transacción.** Es el nivel más bajo que soporta todos los casos de uso pedidos (GMROI necesita item/vendor; promociones necesita `was_on_promo` por ítem). Todo lo demás (GMV por tienda, ticket promedio, Comp Sales) se obtiene agregando hacia arriba — nunca al revés.

---

## 2. Tabla de hechos secundaria (factless fact table)

### `fact_asignacion_promocion` (grano: tienda × experimento × variante)

| Campo | Tipo | Descripción |
|---|---|---|
| `asignacion_key` | STRING (PK) | surrogate |
| `store_key` | STRING (FK → dim_tienda) | |
| `promo_key` | STRING (FK → dim_promocion) | |
| `variant` | STRING | CONTROL / TREATMENT |
| `start_date` | DATE | |
| `end_date` | DATE | |

No tiene medidas numéricas propias ("factless fact table" en terminología Kimball) — captura el *evento* de asignación tienda↔experimento↔variante. Ver decisión de diseño #3 en `bloque2_decisiones.md` sobre por qué esto va separado de `dim_tienda`.

---

## 3. Dimensiones

### `dim_fecha` (dimensión conformada, una fila por día)
`date_key (PK)`, `date`, `year`, `quarter`, `month`, `month_name`, `week_of_year`, `day_of_week`, `is_weekend`

### `dim_tienda`
`store_key (PK)`, `store_id`, `store_name`, `country`, `city`, `format`, `size_sqm`, `opening_date`, `region`

### `dim_producto`
`item_key (PK)`, `item_id`, `item_name`, `brand`, `category`, `department`, `cost`, `vendor_key (FK → dim_proveedor)`

### `dim_proveedor`
`vendor_key (PK)`, `vendor_id`, `vendor_name`, `country`, `tier`, `is_shared_catalog`. Incluye una fila `'UNKNOWN'` para los 5 SKUs con `vendor_id` huérfano detectados en la auditoría (bloque0, hallazgo #5).

### `dim_cliente`
`customer_key (PK)`, `customer_id`, `loyalty_card`, `primera_compra_date`. Incluye una fila `'UNKNOWN'` (customer_key = `'UNKNOWN'`, customer_id = NULL) para las transacciones sin tarjeta de lealtad — ver decisión de diseño #1.

### `dim_promocion`
`promo_key (PK)`, `promo_name`, `promo_type`, `start_date`, `end_date`

---

## 4. Código DBML (pegar directo en dbdiagram.io)

```dbml
Table dim_fecha {
  date_key date [pk]
  year int
  quarter int
  month int
  month_name varchar
  week_of_year int
  day_of_week varchar
  is_weekend boolean
}

Table dim_tienda {
  store_key varchar [pk]
  store_id varchar
  store_name varchar
  country varchar
  city varchar
  format varchar
  size_sqm int
  opening_date date
  region varchar
}

Table dim_producto {
  item_key varchar [pk]
  item_id varchar
  item_name varchar
  brand varchar
  category varchar
  department varchar
  cost float
  vendor_key varchar [ref: > dim_proveedor.vendor_key]
}

Table dim_proveedor {
  vendor_key varchar [pk]
  vendor_id varchar
  vendor_name varchar
  country varchar
  tier varchar
  is_shared_catalog boolean
}

Table dim_cliente {
  customer_key varchar [pk]
  customer_id varchar
  loyalty_card boolean
  primera_compra_date date
}

Table dim_promocion {
  promo_key varchar [pk]
  promo_name varchar
  promo_type varchar
  start_date date
  end_date date
}

Table fact_venta_linea {
  venta_linea_key varchar [pk]
  transaction_id varchar
  date_key date [ref: > dim_fecha.date_key]
  store_key varchar [ref: > dim_tienda.store_key]
  item_key varchar [ref: > dim_producto.item_key]
  customer_key varchar [ref: > dim_cliente.customer_key]
  quantity int
  unit_price float
  line_amount float
  was_on_promo boolean
  status varchar
  payment_method varchar
  total_amount_transaccion float
}

Table fact_asignacion_promocion {
  asignacion_key varchar [pk]
  store_key varchar [ref: > dim_tienda.store_key]
  promo_key varchar [ref: > dim_promocion.promo_key]
  variant varchar
  start_date date
  end_date date
}
```
