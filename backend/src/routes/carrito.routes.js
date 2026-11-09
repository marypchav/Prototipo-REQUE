const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const carrito = require('../controllers/carrito.controller');

const router = Router();

router.get('/', envolver(carrito.obtener));
router.post('/', envolver(carrito.agregar));
router.delete('/', envolver(carrito.vaciar));
router.put('/:id', envolver(carrito.actualizar));
router.delete('/:id', envolver(carrito.quitar));

module.exports = router;
