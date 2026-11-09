/*
Única forma en que el backend habla con la base de datos: ejecutando SP.

Uso:
    const recordsets = await ejecutarSP('spEliminarProducto', {
        inIdUsuario: [sql.Int, 1],
        inIP: [sql.VarChar(64), '127.0.0.1'],
        inIdProducto: [sql.Int, 5],
    });

- Los nombres van SIN la @ (mssql la agrega).
- @outResultCode se agrega solo.
- Si el SP devuelve 0, se retornan sus resultados (recordsets[0], [1], ...).
- Si devuelve otro código, se lanza un ErrorApp con ese código; el manejador
  de errores lo convierte en la respuesta JSON con el mensaje para el usuario.
*/
const { sql, obtenerPool } = require('./conexion');
const ErrorApp = require('../utils/ErrorApp');

async function ejecutarSP(nombreSP, parametros = {}) {
  const pool = await obtenerPool();
  const solicitud = pool.request();

  for (const [nombre, [tipo, valor]] of Object.entries(parametros)) {
    solicitud.input(nombre, tipo, valor === undefined ? null : valor);
  }
  solicitud.output('outResultCode', sql.Int);

  const resultado = await solicitud.execute(`dbo.${nombreSP}`);
  const codigo = resultado.output.outResultCode ?? 50000;

  if (codigo !== 0) {
    // algunos SP devuelven datos junto al error
    // (por ejemplo spConfirmarOrden: la lista de productos no disponibles)
    const datos = resultado.recordsets[0]?.length ? resultado.recordsets[0] : null;
    throw new ErrorApp(codigo, datos);
  }

  return resultado.recordsets;
}

module.exports = { ejecutarSP, sql };
