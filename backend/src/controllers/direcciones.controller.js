/*
CU4: direcciones de envío del cliente (GP003 a GP006).
Cada cliente solo ve y cambia las suyas: el id del usuario sale de la
sesión, nunca del cuerpo de la petición.
*/
const { ejecutarSP, sql } = require('../db/ejecutarSP');
const { aEntero, aTexto, ipDe } = require('../utils/convertir');

function parametrosDireccion(cuerpo = {}) {
  return {
    inIdProvincia: [sql.Int, aEntero(cuerpo.idProvincia)],
    inCanton: [sql.NVarChar(64), aTexto(cuerpo.canton)],
    inDistrito: [sql.NVarChar(64), aTexto(cuerpo.distrito)],
    inOtrasSenas: [sql.NVarChar(256), aTexto(cuerpo.otrasSenas)],
  };
}

// GET /api/direcciones  (GP003)
async function listar(req, res) {
  const [direcciones] = await ejecutarSP('spListarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
  });

  res.json({ ok: true, datos: direcciones });
}

// POST /api/direcciones  (GP004)
// cuerpo: { idProvincia, canton, distrito, otrasSenas }
async function agregar(req, res) {
  const [[fila]] = await ejecutarSP('spAgregarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    ...parametrosDireccion(req.body),
  });

  res.status(201).json({
    ok: true,
    mensaje: 'La dirección fue guardada.',
    datos: { idDireccion: fila.IdDireccion },
  });
}

// PUT /api/direcciones/:id  (GP005)
async function actualizar(req, res) {
  await ejecutarSP('spActualizarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdDireccion: [sql.Int, aEntero(req.params.id)],
    ...parametrosDireccion(req.body),
  });

  res.json({ ok: true, mensaje: 'La dirección fue actualizada con éxito.' });
}

// DELETE /api/direcciones/:id  (GP006)
async function eliminar(req, res) {
  await ejecutarSP('spEliminarDireccion', {
    inIdUsuario: [sql.Int, req.usuario.idUsuario],
    inIP: [sql.VarChar(64), ipDe(req)],
    inIdDireccion: [sql.Int, aEntero(req.params.id)],
  });

  res.json({ ok: true, mensaje: 'La dirección fue eliminada.' });
}

module.exports = { listar, agregar, actualizar, eliminar };
