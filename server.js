require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const pool = require('./db');

const app = express();
const PORT = Number(process.env.PORT) || 3000;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.post('/api/clientes/abm', async (req, res) => {
  const { accion, id, nombre, contacto, ciudad, pais } = req.body;
  try {
    const result = await pool.query(
      'SELECT fn_abm_cliente($1, $2, $3, $4, $5, $6) AS mensaje',
      [accion ?? '', id ?? '', nombre ?? '', contacto ?? '', ciudad ?? '', pais ?? '']
    );
    return res.status(200).json({ ok: true, mensaje: result.rows[0].mensaje });
  } catch (error) {
    console.error('Error en POST /api/clientes/abm:', error.message);
    return res.status(400).json({ ok: false, error: error.message });
  }
});

app.get('/api/ordenes', async (req, res) => {
  const { cliente, empleado } = req.query;
  try {
    const query = `
      SELECT TO_CHAR(orderdate, 'DD/MM/YYYY') AS orderdate, customerid, companyname, employeeid, employname, orderamount
      FROM vw_ordenes
      WHERE companyname ILIKE '%' || $1 || '%'
        AND employname ILIKE '%' || $2 || '%'
      ORDER BY vw_ordenes.orderdate ASC, orderid ASC
    `;
    const result = await pool.query(query, [cliente || '', empleado || '']);
    return res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error en GET /api/ordenes:', error.message);
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.get('/api/clientes', async (req, res) => {
  try {
    const query = `
      SELECT TRIM(customerid) AS customerid, TRIM(companyname) AS companyname, TRIM(COALESCE(contactname, '')) AS contactname, TRIM(COALESCE(city, '')) AS city, TRIM(COALESCE(country, '')) AS country
      FROM customers
      ORDER BY customerid ASC
    `;
    const result = await pool.query(query);
    return res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error en GET /api/clientes:', error.message);
    return res.status(500).json({ ok: false, error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`Servidor activo en http://localhost:${PORT}`);
});
