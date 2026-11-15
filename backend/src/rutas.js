/*
Todas las rutas de la API. Todo cuelga de /api (ver app.js).

Módulo Catálogo de productos (públicas, CP009):
    GET    /api/catalogo?categoria=1&tallas=2,3        CP001 a CP007
    GET    /api/productos/:id                          CP008, CP011

Sesión de la administradora (GI001):
    POST   /api/sesion                                 iniciar sesión
    DELETE /api/sesion                                 cerrar sesión
    GET    /api/sesion                                 quién está conectado

Módulo Gestión de inventario (solo la administradora):
    GET    /api/admin/opciones-producto                categorías y tallas del formulario
    GET    /api/admin/productos?busqueda=&categoria=&tallas=   GI004, GI008
    GET    /api/admin/productos/:id                    GI005 (cargar el formulario)
    POST   /api/admin/productos                        GI002
    PUT    /api/admin/productos/:id                    GI005
    PUT    /api/admin/productos/:id/existencias        GI007
    POST   /api/admin/productos/:id/foto               GI003 (multipart, campo "foto")
    DELETE /api/admin/productos/:id                    GI006
*/
const { Router } = require('express');
const { envolver } = require('./convertir');
const { requiereAdmin } = require('./sesion');
const { subirFotoProducto } = require('./subirImagen');
const catalogo = require('./catalogo.controller');
const sesion = require('./sesion.controller');
const inventario = require('./inventario.controller');

const router = Router();

// módulo Catálogo de productos
router.get('/catalogo', envolver(catalogo.listar));
router.get('/productos/:id', envolver(catalogo.obtener));

// sesión de la administradora
router.post('/sesion', envolver(sesion.iniciar));
router.delete('/sesion', envolver(sesion.cerrar));
router.get('/sesion', envolver(sesion.actual));

// módulo Gestión de inventario: todo lo de /admin pide sesión de administradora
router.use('/admin', requiereAdmin);
router.get('/admin/opciones-producto', envolver(inventario.opciones));
router.get('/admin/productos', envolver(inventario.listar));
router.get('/admin/productos/:id', envolver(inventario.obtener));
router.post('/admin/productos', envolver(inventario.agregar));
router.put('/admin/productos/:id', envolver(inventario.modificar));
router.put('/admin/productos/:id/existencias', envolver(inventario.actualizarExistencias));
router.post('/admin/productos/:id/foto', subirFotoProducto, envolver(inventario.subirFoto));
router.delete('/admin/productos/:id', envolver(inventario.eliminar));

module.exports = router;
