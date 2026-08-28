Prueba Técnica — Data Analyst
Cadena de Retail Multiformato · Centroamérica
Análisis completo de un dataset sintético de 18 meses (ene-2024 a jun-2025), 40 tiendas, 5 países y 4 formatos, cubriendo auditoría de datos, SQL avanzado, modelado dimensional, análisis exploratorio + experimentación, diseño de KPIs, y un dashboard operativo con presentación ejecutiva.
---
📂 Estructura del repositorio
Bloque	Archivo	Contenido
0 — Auditoría	`bloque0_auditoria.md`	9 dimensiones de calidad de datos, con evidencia y decisiones
1 — SQL	`bloque1_queries.sql`	6 queries (Comp Sales, productividad, cohortes, GMROI, quiebres, promociones)
2 — Modelo	`bloque2_modelo.md` · `bloque2_modelo.dbml` · `bloque2_modelo.pdf` · `bloque2_decisiones.md`	Star Schema, decisiones de diseño, pipeline ETL, gobernanza
3 — EDA + A/B Test	`bloque3_analisis.ipynb` · `bloque3_analisis.html` · `bloque3_visualizaciones/`	Estacionalidad, Pareto, cohortes, quiebres, hallazgo libre, interpretación del A/B test
4 — KPIs	`bloque4_kpi_framework.md`	9 KPIs (3 dimensiones, leading indicators, KPI compuesto, North Star) con valores reales calculados
5 — Dashboard + Presentación	`bloque5_dashboard.pbix` · `bloque5_presentacion_EN.pptx`	Dashboard operativo en Power BI + presentación ejecutiva de 5 slides en inglés
—	`data/`	Los 6 CSV originales + 2 tablas de referencia pre-calculadas (cohortes, quiebres activos)
—	`requirements.txt`	Librerías Python necesarias para correr el Bloque 3
---
▶️ Cómo correr el proyecto
Bloque 3 (Jupyter Notebook)
```bash
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
jupyter notebook bloque3_analisis.ipynb
```
Dentro de Jupyter: Kernel → Restart Kernel and Run All Cells. El notebook lee los CSV desde `data/` (ruta relativa) y regenera las 7 imágenes en `bloque3_visualizaciones/` automáticamente al correr.
Bloque 5 (Power BI)
Abre `bloque5_dashboard.pbix` con Power BI Desktop. El modelo se conecta a los CSV en `data/` y a 2 archivos Excel de referencia (`data/bloque5_cohort_retention.xlsx`, `data/bloque5_active_stockouts.xlsx`) — si Power BI pide "actualizar rutas de origen" al abrir, apúntalas a tu copia local de la carpeta `data/`.
Bloques 0, 1, 2, 4
Son documentos de solo lectura (`.md`, `.sql`, `.pdf`, `.dbml`) — no requieren ejecución. El `.sql` del Bloque 1 se validó ejecutándolo contra los CSV reales con DuckDB durante su desarrollo (ver nota de cabecera en el archivo).

---
🤖 Uso de IA
Usé Claude (Anthropic) como asistente durante todo el proyecto, en modalidad de trabajo conversacional e iterativo — no como generador de una sola pasada. A continuación documento honestamente qué generó la IA, qué corregí o dirigí yo, y qué validé de forma independiente, tal como pide el enunciado.
Qué generó la IA
Bloque 0: el código Python de las 8 verificaciones de calidad de datos, a partir de las reglas de negocio que yo definí para cada dimensión.
Bloque 1: la traducción de la lógica de negocio de cada query a SQL (CTEs, window functions), a partir de las reglas y periodos que yo especifiqué.
Bloque 2: el diseño inicial del Star Schema (propuesta de tablas fact/dim) y el código DBML/diagrama; yo definí y justifiqué las decisiones de diseño con mis propias palabras.
Bloque 3: el código de análisis (pandas/matplotlib/scipy) para cada pregunta del EDA y el t-test del A/B test, y la primera versión de las interpretaciones de cada hallazgo.
Bloque 4: la estructura del framework de KPIs y el cálculo de los valores reales de cada uno.
Bloque 5: la guía paso a paso para construir el modelo y las medidas DAX en Power BI, el script de generación de la presentación ejecutiva (`pptxgenjs`), y el diseño visual de los slides.
Qué modifiqué o dirigí yo
Este fue un trabajo de ida y vuelta constante, no una aceptación pasiva del output de la IA. Algunos ejemplos concretos de correcciones y decisiones que tomé durante el proceso:
Pedí explícitamente reemplazar fechas hardcodeadas en el SQL por cálculos dinámicos basados en `MAX(transaction_date)`.
Detecté y corregí una caída falsa en la gráfica de estacionalidad (Bloque 3) causada por una semana parcial al final del dataset — no la dejé pasar como un hallazgo de negocio real.
Detecté celdas en blanco incorrectas en la tabla de cohortes (debían mostrar 0%, no vacío) y pedí el ajuste al código.
Cuestioné cómo se manejaba la moneda del dataset (no asumí "USD" sin verificar) — se agregó como hallazgo explícito en la auditoría.
En Power BI, detecté que el ranking de "bajo rendimiento" daba 17 tiendas en vez de las 10 esperadas, lo que llevó a encontrar un error real en una fórmula DAX (`ALLEXCEPT` mal usado).
Insistí en verificar el filtro "Top N" de un gráfico cuando el diseño no tenía sentido (comparar contra el ranking de las mejores tiendas, no las peores).
Pedí explícitamente que el header del dashboard fuera "fijo" a la última semana real, sin necesitar instrucciones para el usuario final — alineado con el requisito del enunciado de que el dashboard se use "sin soporte técnico".
Encontré y reporté una relación fantasma en dos tablas del modelo de Power BI (originada por copiar-pegar un visual existente en vez de crear uno nuevo).
Definí yo mismo los nombres de las tablas siguiendo la convención `fact_`/`dim_`, y el diseño final del dashboard (colores de marca, disposición de las tarjetas).
Qué validé manualmente
Cada resultado numérico importante de este proyecto se validó de forma cruzada, casi siempre con una segunda implementación independiente en Python (pandas/DuckDB) de la misma lógica:
Los 6 resultados de las queries SQL del Bloque 1 se corrieron contra los CSV reales con DuckDB antes de darlos por buenos.
Los resultados del t-test del A/B test (Bloque 3) se calcularon con `scipy.stats` y se verificaron paso a paso (validación del experimento, GMV, descomposición ticket/frecuencia).
Las medidas DAX de Power BI (Net GMV, ticket promedio, GMV/m², variación semanal, retención de cohorte semana 4, percentil 25 de bajo rendimiento) se compararon número por número contra cálculos equivalentes en Python — con coincidencia exacta en cada caso antes de aceptar la medida como correcta.
Los 9 valores del framework de KPIs (Bloque 4) se recalcularon con datos reales, no se dejaron como fórmulas teóricas sin verificar.
Limitaciones conocidas de este enfoque
Las tablas de cohortes y de quiebres de stock activos en el dashboard de Power BI (Bloque 5) se cargan como datos pre-calculados en Python, no como DAX nativo — una decisión deliberada para reusar lógica ya validada en vez de reimplementarla con más riesgo de error, documentada en el propio dashboard. En un pipeline de producción real, esto se automatizaría (p. ej. con dbt o una vista SQL programada), no se pegaría a mano.
Varios hallazgos del Bloque 3 (quiebres de stock afectando el 100% del catálogo, retención de cohortes no monótona, mix de categorías idéntico entre formatos) se documentan explícitamente como probables artefactos del generador de datos sintéticos, no como conclusiones de negocio a implementar tal cual — evité sobre-interpretar patrones que no se sostienen con el rigor esperado de un hallazgo real.
