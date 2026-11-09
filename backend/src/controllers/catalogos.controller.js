/*
Catálogos para llenar las listas desplegables del frontend.
*/
const { ejecutarSP } = require('../db/ejecutarSP');

// GET /api/catalogos
async function obtenerCatalogos(req, res) {
  const [categorias, tallas, provincias, metodosPago, metodosEntrega, estadosPedido] =
    await ejecutarSP('spObtenerCatalogos');

  res.json({
    ok: true,
    datos: { categorias, tallas, provincias, metodosPago, metodosEntrega, estadosPedido },
  });
}

module.exports = { obtenerCatalogos };
