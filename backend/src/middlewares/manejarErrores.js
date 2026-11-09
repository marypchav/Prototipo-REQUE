/*
Todas las respuestas de error tienen la misma forma:
    { "ok": false, "codigo": 50008, "mensaje": "El precio debe ser mayor que cero." }
El frontend solo tiene que mostrar "mensaje".
*/
const multer = require('multer');
const ErrorApp = require('../utils/ErrorApp');
const { borrarArchivo } = require('./subirImagen');

function rutaNoEncontrada(req, res, next) {
  next(new ErrorApp(50031));
}

// eslint-disable-next-line no-unused-vars
async function manejarErrores(error, req, res, next) {
  let errorFinal = error;

  if (error instanceof multer.MulterError) {
    errorFinal = new ErrorApp(error.code === 'LIMIT_FILE_SIZE' ? 50029 : 50012);
  } else if (error.type === 'entity.parse.failed') {
    errorFinal = new ErrorApp(50032); // JSON mal formado
  } else if (!(error instanceof ErrorApp)) {
    // error no esperado: se muestra en consola para depurar,
    // al usuario solo le llega el mensaje genérico
    console.error(error);
    errorFinal = new ErrorApp(50000);
  }

  // si se subió una imagen pero la operación falló, no se deja basura en disco
  if (req.file) {
    await borrarArchivo(req.file.path);
  }

  res.status(errorFinal.estadoHttp).json({
    ok: false,
    codigo: errorFinal.codigo,
    mensaje: errorFinal.message,
    ...(errorFinal.datos ? { datos: errorFinal.datos } : {}),
  });
}

module.exports = { rutaNoEncontrada, manejarErrores };
