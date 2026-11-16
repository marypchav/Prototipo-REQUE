/*
Imágenes que suben los usuarios, con multer. Solo PNG o JPG, máximo 5 MB,
con un nombre único.

GI003 Foto del producto (campo "foto"):
  - Se guarda en backend/uploads/productos
  - En la base va "uploads/productos/archivo.jpg", y el navegador la pide en
    http://localhost:3000/uploads/productos/archivo.jpg (es pública)

GP013 Comprobante de SINPE Móvil (campo "comprobante"):
  - Se guarda en backend/uploads/comprobantes
  - NO es pública: tiene datos de pago. Solo se entrega por la API, al dueño
    del pedido o a la administradora (ver pedidos.controller.js)
*/
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const ErrorApp = require('./ErrorApp');

const MAX_MB = 5;
const RAIZ_BACKEND = path.join(__dirname, '..');
const RAIZ_UPLOADS = path.join(RAIZ_BACKEND, 'uploads');
const CARPETA_PRODUCTOS = path.join(RAIZ_UPLOADS, 'productos');
const CARPETA_COMPROBANTES = path.join(RAIZ_UPLOADS, 'comprobantes');

const extensionPorTipo = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
};

fs.mkdirSync(CARPETA_PRODUCTOS, { recursive: true });
fs.mkdirSync(CARPETA_COMPROBANTES, { recursive: true });

// middleware que recibe UNA imagen del campo indicado y la guarda en la carpeta
function subirImagenA(carpeta, campo) {
  return multer({
    storage: multer.diskStorage({
      destination: carpeta,
      filename: (req, archivo, cb) => {
        const aleatorio = crypto.randomBytes(4).toString('hex');
        cb(null, `${Date.now()}_${aleatorio}${extensionPorTipo[archivo.mimetype]}`);
      },
    }),
    limits: {
      fileSize: MAX_MB * 1024 * 1024,
      files: 1,
    },
    fileFilter: (req, archivo, cb) => {
      if (extensionPorTipo[archivo.mimetype]) {
        cb(null, true);
      } else {
        cb(new ErrorApp(50027)); // formato no permitido (GI003 y GP013 flujo alternativo)
      }
    },
  }).single(campo);
}

const subirFotoProducto = subirImagenA(CARPETA_PRODUCTOS, 'foto');
const subirComprobante = subirImagenA(CARPETA_COMPROBANTES, 'comprobante');

// ruta que se guarda en la base para un archivo recién subido
function rutaRelativa(archivo) {
  return path.relative(RAIZ_BACKEND, archivo.path).split(path.sep).join('/');
}

// borra una foto de uploads; ignora rutas fuera de uploads y archivos que ya no existen
async function borrarArchivo(ruta) {
  if (!ruta) {
    return;
  }
  const absoluta = path.resolve(RAIZ_BACKEND, ruta);
  if (!absoluta.startsWith(RAIZ_UPLOADS + path.sep)) {
    return; // por ejemplo las fotos de muestra de frontend/img: no se tocan
  }
  try {
    await fs.promises.unlink(absoluta);
  } catch {
    // ya no existía
  }
}

// ruta absoluta de un comprobante guardado en la base, o null si la ruta no
// está dentro de uploads/comprobantes (así nadie puede pedir otro archivo)
function rutaAbsolutaComprobante(ruta) {
  if (!ruta) {
    return null;
  }
  const absoluta = path.resolve(RAIZ_BACKEND, ruta);
  return absoluta.startsWith(CARPETA_COMPROBANTES + path.sep) ? absoluta : null;
}

module.exports = {
  subirFotoProducto,
  subirComprobante,
  rutaRelativa,
  borrarArchivo,
  rutaAbsolutaComprobante,
};
