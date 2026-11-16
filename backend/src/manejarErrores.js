/*
Todas las respuestas de error tienen la misma forma:
    { "ok": false, "codigo": 50011, "mensaje": "Este producto ya no está disponible." }
El frontend solo tiene que mostrar "mensaje".
*/
const multer = require('multer');
const ErrorApp = require('./ErrorApp');
const { borrarArchivo } = require('./subirImagen');

function rutaNoEncontrada(req, res, next) {
  next(new ErrorApp(50031));
}

// eslint-disable-next-line no-unused-vars
async function manejarErrores(error, req, res, next) {
  let errorFinal = error;

  if (error instanceof multer.MulterError) {
    // imagen de más de 5 MB, o un campo de archivo que no es "foto"
    errorFinal = new ErrorApp(error.code === 'LIMIT_FILE_SIZE' ? 50035 : 50027);
  } else if (error.type === 'entity.parse.failed') {
    errorFinal = new ErrorApp(50032); // JSON mal formado
  } else if (!(error instanceof ErrorApp)) {
    // error no esperado: se muestra en consola para depurar,
    // al usuario solo le llega el mensaje genérico
    console.error(error);
    errorFinal = new ErrorApp(50000);
  }

  // si se subió una foto pero la operación falló, no se deja basura en disco
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
