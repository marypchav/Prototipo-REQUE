/*
Configuración de Express: middlewares, rutas y archivos estáticos.
El mismo servidor entrega la API (/api), las fotos de productos
(/uploads/productos) y la página web (carpeta frontend).
*/
const path = require('path');
const express = require('express');

const rutas = require('./rutas');
const { rutaNoEncontrada, manejarErrores } = require('./manejarErrores');

const RAIZ_BACKEND = path.join(__dirname, '..');
const RAIZ_FRONTEND = path.join(RAIZ_BACKEND, '..', 'frontend');

const app = express();

app.disable('x-powered-by'); // no anunciar que el servidor es Express

app.use(express.json({ limit: '100kb' }));

// API
app.use('/api', rutas);
app.use('/api', rutaNoEncontrada);

// fotos que sube la administradora (módulo Gestión de inventario, GI003).
// Producto.RutaImagen guarda "uploads/productos/archivo.jpg"
app.use('/uploads/productos', express.static(path.join(RAIZ_BACKEND, 'uploads', 'productos')));

// página web (incluye las fotos de muestra de frontend/img/productos)
app.use(express.static(RAIZ_FRONTEND));

// siempre de último
app.use(manejarErrores);

module.exports = app;
