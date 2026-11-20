CREATE OR REPLACE FUNCTION fn_abm_cliente(
    IN pv_accion   TEXT,
    IN pv_id       TEXT,
    IN pv_nombre   TEXT,
    IN pv_contacto TEXT,
    IN pv_ciudad   TEXT,
    IN pv_pais     TEXT
)
RETURNS TEXT
AS $$
DECLARE
    lv_accion   TEXT := UPPER(TRIM(COALESCE(pv_accion, '')));
    lv_id       TEXT := UPPER(TRIM(COALESCE(pv_id, '')));
    lv_nombre   TEXT := TRIM(COALESCE(pv_nombre, ''));
    lv_contacto TEXT := NULLIF(TRIM(COALESCE(pv_contacto, '')), '');
    lv_ciudad   TEXT := NULLIF(TRIM(COALESCE(pv_ciudad, '')), '');
    lv_pais     TEXT := NULLIF(TRIM(COALESCE(pv_pais, '')), '');
BEGIN
    IF lv_accion NOT IN ('A', 'M', 'B') THEN
        RAISE EXCEPTION 'Acción inválida: %. Debe indicar A (Alta), M (Modificación) o B (Baja).', pv_accion;
    END IF;

    IF lv_id !~ '^[A-Z]{5}$' THEN
        RAISE EXCEPTION 'El código de cliente debe tener exactamente 5 letras.';
    END IF;

    IF lv_accion = 'A' THEN
        IF lv_nombre = '' THEN
            RAISE EXCEPTION 'El nombre de la compañía es obligatorio para el alta.';
        END IF;

        IF EXISTS (SELECT 1 FROM customers WHERE TRIM(customerid) = lv_id) THEN
            RAISE EXCEPTION 'Ya existe un cliente registrado con el código %.', lv_id;
        END IF;

        INSERT INTO customers (customerid, companyname, contactname, city, country)
        VALUES (lv_id, lv_nombre, lv_contacto, lv_ciudad, lv_pais);

        RETURN 'Cliente ' || lv_id || ' dado de alta correctamente.';

    ELSIF lv_accion = 'M' THEN
        IF NOT EXISTS (SELECT 1 FROM customers WHERE TRIM(customerid) = lv_id) THEN
            RAISE EXCEPTION 'No existe ningún cliente con el código % para modificar.', lv_id;
        END IF;

        IF lv_nombre = '' THEN
            RAISE EXCEPTION 'El nombre de la compañía no puede quedar vacío.';
        END IF;

        UPDATE customers
        SET companyname = lv_nombre,
            contactname = lv_contacto,
            city        = lv_ciudad,
            country     = lv_pais
        WHERE TRIM(customerid) = lv_id;

        RETURN 'Cliente ' || lv_id || ' modificado correctamente.';

    ELSIF lv_accion = 'B' THEN
        IF NOT EXISTS (SELECT 1 FROM customers WHERE TRIM(customerid) = lv_id) THEN
            RAISE EXCEPTION 'No existe ningún cliente con el código % para eliminar.', lv_id;
        END IF;

        IF EXISTS (SELECT 1 FROM orders WHERE TRIM(customerid) = lv_id) THEN
            RAISE EXCEPTION 'No se puede eliminar el cliente % porque registra órdenes asociadas.', lv_id;
        END IF;

        DELETE FROM customers WHERE TRIM(customerid) = lv_id;

        RETURN 'Cliente ' || lv_id || ' eliminado correctamente.';
    END IF;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE VIEW vw_ordenes AS
SELECT 
    o.orderid,
    o.orderdate,
    TRIM(c.customerid)::VARCHAR(5) AS customerid,
    TRIM(c.companyname)::VARCHAR(40) AS companyname,
    e.employeeid,
    (TRIM(e.lastname) || ' ' || TRIM(e.firstname))::VARCHAR(60) AS employname,
    ROUND(COALESCE(SUM(od.unitprice * od.quantity * (1 - od.discount)), 0), 2)::NUMERIC(12,2) AS orderamount
FROM orders o
INNER JOIN customers c     ON o.customerid = c.customerid
INNER JOIN employees e     ON o.employeeid = e.employeeid
LEFT JOIN orderdetails od  ON o.orderid = od.orderid
GROUP BY o.orderid, o.orderdate, c.customerid, c.companyname, e.employeeid, e.lastname, e.firstname;
