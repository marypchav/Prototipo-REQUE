/*
GI003 Subir foto del producto, con multer.
- Solo PNG o JPG (GI003 restricción 1)
- Máximo 5 MB
- Se guarda en backend/uploads/productos con un nombre único
- En la base va la ruta relativa: "uploads/productos/archivo.jpg", y el
  navegador la pide en http://localhost:3000/uploads/productos/archivo.jpg
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

const extensionPorTipo = {
  'image/png': '.png',
  'image/jpeg': '.jpg',
};

fs.mkdirSync(CARPETA_PRODUCTOS, { recursive: true });

// middleware: recibe el archivo del campo "foto" del formulario
const subirFotoProducto = multer({
  storage: multer.diskStorage({
    destination: CARPETA_PRODUCTOS,
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
      cb(new ErrorApp(50027)); // formato no permitido (GI003 flujo alternativo)
    }
  },
}).single('foto');

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

module.exports = { subirFotoProducto, rutaRelativa, borrarArchivo };
