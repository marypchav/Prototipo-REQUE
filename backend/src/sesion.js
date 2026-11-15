/*
Sesión de la administradora (GI001), guardada en una cookie httpOnly:
el JavaScript del navegador no la puede leer, así que no se puede robar
con un script.

- crearSesion: al iniciar sesión, guarda quién es en la cookie
- cerrarSesion: borra la cookie
- leerSesion: en cada petición deja en req.usuario quién es (o null)
- requiereAdmin: bloquea las rutas de inventario si no es la administradora
  (sección 2.4 de la ERS)
*/
const jwt = require('jsonwebtoken');
const config = require('./env');
const ErrorApp = require('./ErrorApp');

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
    esAdministrador: true, // por ahora solo inicia sesión la administradora
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

function requiereAdmin(req, res, next) {
  if (!req.usuario) {
    return next(new ErrorApp(50033)); // debe iniciar sesión
  }
  if (!req.usuario.esAdministrador) {
    return next(new ErrorApp(50034)); // sin permiso
  }
  next();
}

module.exports = { crearSesion, cerrarSesion, leerSesion, requiereAdmin };
