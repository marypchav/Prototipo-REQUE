/*
Configuración de Express: middlewares, rutas y archivos estáticos.
El mismo servidor entrega la API (/api), las imágenes (/uploads) y la
página web (carpeta frontend). Así todo vive en el mismo dominio y la
cookie de sesión funciona sin configurar CORS.
*/
const path = require('path');
const express = require('express');
const cookieParser = require('cookie-parser');

const rutas = require('./routes');
const { leerSesion } = require('./middlewares/autenticacion');
const { RAIZ_UPLOADS } = require('./middlewares/subirImagen');
const { rutaNoEncontrada, manejarErrores } = require('./middlewares/manejarErrores');

const RAIZ_FRONTEND = path.join(__dirname, '..', '..', 'frontend');

const app = express();

app.disable('x-powered-by'); // no anunciar que el servidor es Express

app.use(express.json({ limit: '100kb' }));
app.use(cookieParser());
app.use(leerSesion);

// API
app.use('/api', rutas);
app.use('/api', rutaNoEncontrada);

// fotos de productos: públicas. Los comprobantes SINPE NO se publican aquí
// (tienen datos personales): se piden por /api/pedidos/:id/comprobante
app.use('/uploads/productos', express.static(path.join(RAIZ_UPLOADS, 'productos')));

// página web
app.use(express.static(RAIZ_FRONTEND));

// siempre de último
app.use(manejarErrores);

module.exports = app;
