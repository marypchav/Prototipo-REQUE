/*
Sesión con JWT guardado en una cookie httpOnly: el JavaScript del navegador
no la puede leer, así que un script malicioso no puede robar la sesión.

- leerSesion: en cada petición deja en req.usuario quién es (o null)
- requiereSesion: bloquea si no hay sesión (carrito, direcciones, pedidos)
- requiereAdmin: bloquea si no es la administradora (sección 2.4 de la ERS:
  las rutas de inventario y confirmación de pedidos se bloquean)

Los SP vuelven a revisar el rol: si algo se escapara aquí, la base lo frena.
*/
const jwt = require('jsonwebtoken');
const config = require('../config/env');
const ErrorApp = require('../utils/ErrorApp');

const NOMBRE_COOKIE = 'capanni_sesion';

const opcionesCookie = {
  httpOnly: true,
  sameSite: 'lax',
  secure: config.esProduccion, // en producción solo viaja por HTTPS
};

function crearSesion(res, usuario) {
  const datos = {
    idUsuario: usuario.IdUsuario,
    nombre: usuario.Nombre,
    esAdministrador: Boolean(usuario.EsAdministrador),
  };
  const token = jwt.sign(datos, config.jwt.secreto, { expiresIn: `${config.jwt.horas}h` });

  res.cookie(NOMBRE_COOKIE, token, {
    ...opcionesCookie,
    maxAge: config.jwt.horas * 60 * 60 * 1000,
  });

  return datos;
}

function cerrarSesion(res) {
  res.clearCookie(NOMBRE_COOKIE, opcionesCookie);
}

function leerSesion(req, res, next) {
  req.usuario = null;
  const token = req.cookies?.[NOMBRE_COOKIE];

  if (token) {
    try {
      req.usuario = jwt.verify(token, config.jwt.secreto);
    } catch {
      cerrarSesion(res); // vencida o alterada: se borra
    }
  }
  next();
}

function requiereSesion(req, res, next) {
  if (!req.usuario) {
    return next(new ErrorApp(50030));
  }
  next();
}

function requiereAdmin(req, res, next) {
  if (!req.usuario) {
    return next(new ErrorApp(50030));
  }
  if (!req.usuario.esAdministrador) {
    return next(new ErrorApp(50002));
  }
  next();
}

module.exports = {
  NOMBRE_COOKIE,
  crearSesion,
  cerrarSesion,
  leerSesion,
  requiereSesion,
  requiereAdmin,
};
