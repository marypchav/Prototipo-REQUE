/*
Todas las respuestas de error tienen la misma forma:
    { "ok": false, "codigo": 50011, "mensaje": "Este producto ya no está disponible." }
*/
const ErrorApp = require('./ErrorApp');

function rutaNoEncontrada(req, res, next) {
  next(new ErrorApp(50031));
}

function manejarErrores(error, req, res, next) {
  let errorFinal = error;

  if (error.type === 'entity.parse.failed') {
    errorFinal = new ErrorApp(50032); // JSON mal formado
  } else if (!(error instanceof ErrorApp)) {
    // error no esperado: se muestra en consola,
    // al usuario solo le llega el mensaje genérico
    console.error(error);
    errorFinal = new ErrorApp(50000);
  }

  res.status(errorFinal.estadoHttp).json({
    ok: false,
    codigo: errorFinal.codigo,
    mensaje: errorFinal.message,
    ...(errorFinal.datos ? { datos: errorFinal.datos } : {}),
  });
}

module.exports = { rutaNoEncontrada, manejarErrores };
