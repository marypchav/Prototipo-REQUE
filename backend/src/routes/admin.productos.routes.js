/*
CU1 Gestión de inventario. Todas estas rutas pasan antes por requiereAdmin
(se aplica en routes/index.js).
*/
const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const productos = require('../controllers/productos.controller');
const { subirFotoProducto } = require('../middlewares/subirImagen');

const router = Router();

router.get('/', envolver(productos.listarAdmin));
router.post('/', envolver(productos.agregar));
router.put('/:id', envolver(productos.actualizar));
router.delete('/:id', envolver(productos.eliminar));
router.put('/:id/tallas/:idTalla', envolver(productos.actualizarDisponibilidad));
router.post('/:id/foto', subirFotoProducto, envolver(productos.subirFoto));

module.exports = router;
