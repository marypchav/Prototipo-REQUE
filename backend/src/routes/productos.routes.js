/*
Rutas públicas de productos (CP009: sin iniciar sesión).
El listado del catálogo (spListarCatalogo) se agrega con el CU2.
*/
const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const productos = require('../controllers/productos.controller');

const router = Router();

router.get('/:id', envolver(productos.obtener));

module.exports = router;
