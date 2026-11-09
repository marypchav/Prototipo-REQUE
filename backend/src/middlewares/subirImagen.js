/*
Subida de imágenes con multer (fotos de productos y comprobantes SINPE).
- Solo PNG o JPG (GI003, GP013)
- Máximo 5 MB (GP013)
- Se guardan en backend/uploads/<carpeta>/ con un nombre único
- En la base se guarda la ruta relativa: "uploads/productos/archivo.jpg"
  y el navegador la pide en http://localhost:3000/uploads/productos/archivo.jpg
*/
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const config = require('../config/env');
const ErrorApp = require('../utils/ErrorApp');

const RAIZ_BACKEND = path.join(__dirname, '..', '..');
const RAIZ_UPLOADS = path.join(RAIZ_BACKEND, 'uploads');

const extensionPorTipo = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
};

function crearSubida(carpeta, nombreCampo) {
  const destino = path.join(RAIZ_UPLOADS, carpeta);
  fs.mkdirSync(destino, { recursive: true });

  return multer({
    storage: multer.diskStorage({
      destination: destino,
      filename: (req, archivo, cb) => {
        const aleatorio = crypto.randomBytes(4).toString('hex');
        cb(null, `${Date.now()}_${aleatorio}${extensionPorTipo[archivo.mimetype]}`);
      },
    }),
    limits: {
      fileSize: config.maxImagenMB * 1024 * 1024,
      files: 1,
    },
    fileFilter: (req, archivo, cb) => {
      if (extensionPorTipo[archivo.mimetype]) {
        cb(null, true);
      } else {
        cb(new ErrorApp(50012));
      }
    },
  }).single(nombreCampo);
}

// ruta que se guarda en la base para un archivo recién subido
function rutaRelativa(archivo) {
  return path.relative(RAIZ_BACKEND, archivo.path).split(path.sep).join('/');
}

// ruta absoluta de un archivo de uploads; null si la ruta apunta fuera de uploads
function rutaAbsoluta(ruta) {
  if (!ruta) {
    return null;
  }
  const absoluta = path.resolve(RAIZ_BACKEND, ruta);
  return absoluta.startsWith(RAIZ_UPLOADS + path.sep) ? absoluta : null;
}

// borra un archivo de uploads; ignora rutas fuera de uploads y archivos inexistentes
async function borrarArchivo(ruta) {
  const absoluta = rutaAbsoluta(ruta);
  if (!absoluta) {
    return;
  }
  try {
    await fs.promises.unlink(absoluta);
  } catch {
    // ya no existía: no pasa nada
  }
}

module.exports = {
  RAIZ_UPLOADS,
  subirFotoProducto: crearSubida('productos', 'foto'),
  subirComprobante: crearSubida('comprobantes', 'comprobante'),
  rutaRelativa,
  rutaAbsoluta,
  borrarArchivo,
};
