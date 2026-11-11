/*
Todas las rutas de la API
*/
const { Router } = require('express');
const { envolver } = require('./convertir');
const catalogo = require('./catalogo.controller');

const router = Router();

// módulo Catálogo de productos
router.get('/catalogo', envolver(catalogo.listar));
router.get('/productos/:id', envolver(catalogo.obtener));

module.exports = router;
