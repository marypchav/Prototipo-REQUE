const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const auth = require('../controllers/auth.controller');

const router = Router();

router.post('/registro', envolver(auth.registrar));
router.post('/login', envolver(auth.iniciarSesion));
router.post('/logout', envolver(auth.salir));
router.get('/yo', envolver(auth.quienSoy));

module.exports = router;
