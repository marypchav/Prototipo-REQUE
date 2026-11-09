/*
CU2: catálogo público (CP001 a CP007, CP009). No requiere sesión.
*/
const { ejecutarSP, sql } = require('../db/ejecutarSP');
const { aEntero, agruparTallas } = require('../utils/convertir');

// "2,3" -> '[2,3]'; un valor que no sea número queda null y el SP responde 50010
function tallasDeConsulta(valor) {
  if (valor === undefined || valor === null || String(valor).trim() === '') {
    return null;
  }
  const ids = String(valor)
    .split(',')
    .map((parte) => aEntero(parte.trim()));
  return JSON.stringify(ids);
}

// GET /api/catalogo?categoria=1&tallas=2,3
async function listar(req, res) {
  const [productos, tallas, categoriasFiltro, tallasFiltro] = await ejecutarSP('spListarCatalogo', {
    inIdCategoria: [sql.Int, aEntero(req.query.categoria)],
    inTallasJson: [sql.NVarChar(sql.MAX), tallasDeConsulta(req.query.tallas)],
  });

  res.json({
    ok: true,
    datos: {
      productos: agruparTallas(productos, tallas), // cada tarjeta con sus tallas disponibles
      filtros: {
        categorias: categoriasFiltro, // solo las que tienen productos (CP007)
        tallas: tallasFiltro, // solo las que tienen existencias (CP006)
      },
    },
  });
}

module.exports = { listar };
