const { Router } = require('express');
const { envolver } = require('../utils/convertir');
const catalogo = require('../controllers/catalogo.controller');

const router = Router();

router.get('/', envolver(catalogo.listar));

module.exports = router;
