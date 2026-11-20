# Informe Técnico — Trabajo Integrador

**Asignatura:** Programación Avanzada en Bases de Datos / Bases de Datos II  
**Institución:** Universidad Nacional de Salta (UNSa)  
**Base de Datos:** PostgreSQL (`northwind`)

---

## 1. Herramienta

El sistema fue desarrollado adoptando una arquitectura cliente-servidor liviana donde la lógica de negocio, integridad y validación reside íntegramente en el motor relacional **PostgreSQL**, relegando a la aplicación el rol de interfaz de presentación, transporte de parámetros y visualización de resultados.

- **Entorno Backend:** **Node.js (v20+)** sobre el framework **Express**, encargado de servir los recursos estáticos y exponer una capa mínima de ruteo HTTP que traduce peticiones JSON en llamadas parametrizadas a objetos almacenados en la base de datos.
- **Diseño Frontend:** Interfaz web construida en **HTML5, CSS3 y JavaScript (Fetch API)** en un único documento (`public/index.html`) organizado en dos vistas tabulares:
  1. **Consulta de Órdenes (Vista `vw_ordenes`):** Permite filtrar dinámicamente por nombre de compañía y empleado e inspeccionar los totales calculados en el servidor de base de datos.
  2. **ABM de Clientes (Función `fn_abm_cliente`):** Presenta un formulario deliberadamente libre de restricciones HTML5 (`required`, `maxlength`, `pattern`) junto a una grilla interactiva de selección rápida, permitiendo que cualquier entrada inválida viaje hasta PostgreSQL para demostrar en pantalla la captura de excepciones generadas mediante `RAISE EXCEPTION`.

---

## 2. Driver y Estrategia de Conexión

La comunicación con el motor PostgreSQL se implementó mediante el driver oficial **`node-postgres` (`pg`)** en conjunto con **`dotenv`** para la parametrización de credenciales a través de variables de entorno (`.env`).

- **Pool de Conexiones:** En el módulo `db.js` se instancia un objeto `Pool` que administra conexiones persistentes sobre el protocolo TCP/IP hacia el puerto por defecto `5432`. Esta estrategia evita la sobrecarga de apertura y cierre de sockets TCP en cada transacción HTTP, reutilizando conexiones activas de forma eficiente.
- **Consultas Preparadas y Seguridad:** Todas las interacciones con PostgreSQL emplean consultas parametrizadas con marcadores posicionales tipados (`$1` a `$6`). El protocolo extendido de consulta de PostgreSQL separa el árbol sintáctico de la sentencia SQL respecto de los valores suministrados por el usuario, neutralizando de raíz cualquier vector de **inyección SQL (SQL Injection)**.
- **Manejo Transaccional y Propagación de Errores:** Dado que las operaciones de alta, modificación y baja se ejecutan dentro de una única invocación a la función `fn_abm_cliente` en lenguaje `plpgsql`, PostgreSQL garantiza la atomicidad transaccional de la ejecución: si alguna regla de negocio falla y dispara `RAISE EXCEPTION`, el motor revierte automáticamente cualquier cambio parcial y el bloque `try/catch` de Express intercepta `error.message` para responder con estado `HTTP 400`.

---

## 3. Llamadas a los Objetos de Base de Datos

Siguiendo la directriz arquitectónica de la cátedra, el código de Node.js carece por completo de sentencias de manipulación directa sobre tablas y opera exclusivamente sobre los objetos definidos en `sql/integrador.sql`:

### 3.1. Función Almacenada `fn_abm_cliente`
Centraliza el alta (`A`), modificación (`M`) y baja (`B`) de la entidad `customers` respetando la convención de prefijos `pv_` para parámetros de entrada y `lv_` para variables locales normalizadas. Desde Express se invoca mediante:

```sql
SELECT fn_abm_cliente($1, $2, $3, $4, $5, $6) AS mensaje
```

Adentro del bloque `plpgsql`, la función sanea los argumentos (`TRIM`, `UPPER`, `COALESCE`, `NULLIF`), valida mediante expresiones regulares que el identificador posea exactamente 5 caracteres alfabéticos (`^[A-Z]{5}$`), comprueba unicidad o existencia previa según la acción solicitada y verifica la ausencia de órdenes dependientes antes de proceder con una eliminación.

### 3.2. Vista `vw_ordenes`
Encapsula las uniones (`INNER JOIN` con `customers` y `employees`, y `LEFT JOIN` con `orderdetails`) junto con el cálculo agregado del monto total de cada orden aplicando descuentos (`ROUND(COALESCE(SUM(od.unitprice * od.quantity * (1 - od.discount)), 0), 2)::NUMERIC(12,2)`). La aplicación consulta esta vista utilizando coincidencia parcial insensible a mayúsculas y minúsculas (`ILIKE`):

```sql
SELECT TO_CHAR(orderdate, 'DD/MM/YYYY') AS orderdate, customerid, companyname, employeeid, employname, orderamount
FROM vw_ordenes
WHERE companyname ILIKE '%' || $1 || '%'
  AND employname ILIKE '%' || $2 || '%'
ORDER BY vw_ordenes.orderdate ASC, orderid ASC
```

---

## 4. Dificultades y Soluciones Implementadas

1. **Espacios en Blanco por Herencia de Tipos `CHAR(n)` (`bpchar`) en Northwind:**
   - **Problema:** En el esquema clásico de la base de datos `northwind`, columnas como `customerid` fueron definidas históricamente con tipo de longitud fija (`CHAR(5)` / `bpchar`), lo que rellena con espacios a la derecha los valores almacenados y provoca discrepancias en comparaciones exactas o cadenas concatenadas en el cliente web.
   - **Solución:** Se aplicó la función `TRIM()` tanto en las condiciones de búsqueda e integridad dentro de `fn_abm_cliente` (`WHERE TRIM(customerid) = lv_id`) como en las proyecciones y conversiones explícitas de la vista `vw_ordenes` (`TRIM(c.customerid)::VARCHAR(5)`), asegurando datos limpios y comparaciones deterministas.

2. **Control de Integridad Referencial en Bajas de Clientes con Órdenes Activas:**
   - **Problema:** Intentar eliminar un registro de `customers` que posee tuplas asociadas en la tabla `orders` produce un fallo crudo de clave foránea en el motor o impide al usuario final comprender la causa exacta del rechazo.
   - **Solución:** Antes de ejecutar la baja en `fn_abm_cliente`, se incorporó una verificación explícita de existencia (`IF EXISTS (SELECT 1 FROM orders WHERE TRIM(customerid) = lv_id)`) que intercepta la condición y lanza una excepción controlada y descriptiva (`RAISE EXCEPTION 'No se puede eliminar el cliente % porque registra órdenes asociadas.', lv_id`), la cual es capturada por el backend y presentada de forma clara en el panel de notificaciones de la interfaz.

3. **Tratamiento de Cadenas Vacías y Valores Nulos desde el Frontend:**
   - **Problema:** Los formularios web envían cadenas vacías (`""`) o compuestas únicamente por espacios cuando el operador omite campos opcionales (`contactname`, `city`, `country`) o deja en blanco campos obligatorios (`companyname`).
   - **Solución:** En la sección `DECLARE` de `fn_abm_cliente` se normalizaron las entradas combinando `TRIM(COALESCE(...))` con `NULLIF(..., '')` para almacenar `NULL` semántico en los atributos opcionales vacíos, y se validó explícitamente que `lv_nombre` no resulte vacío en las operaciones de alta y modificación antes de afectar la tabla.
