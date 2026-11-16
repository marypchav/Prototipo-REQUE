/*
Sesión de la administradora (GI001) y del cliente (GP002), guardada en una
cookie httpOnly: el JavaScript del navegador no la puede leer, así que no se
puede robar con un script.

- crearSesion: al iniciar sesión, guarda quién es en la cookie
- cerrarSesion: borra la cookie
- leerSesion: en cada petición deja en req.usuario quién es (o null)
- requiereAdmin: bloquea las rutas de administración si no es la
  administradora (sección 2.4 de la ERS)
- requiereCliente: bloquea carrito, direcciones y pedidos si no hay sesión
  de cliente (GP002 restricción 3: una cuenta no puede ser las dos cosas)
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

// esAdministrador lo decide quien llama, según el SP que validó la cuenta:
// spObtenerCredencialAdmin (true) o spObtenerCredencialCliente (false)
function crearSesion(res, usuario, { esAdministrador }) {
  const datos = {
    idUsuario: usuario.IdUsuario,
    nombre: usuario.Nombre,
    esAdministrador: Boolean(esAdministrador),
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

function requiereCliente(req, res, next) {
  if (!req.usuario) {
    return next(new ErrorApp(50033)); // debe iniciar sesión (GP007 flujo alterno 1)
  }
  if (req.usuario.esAdministrador) {
    return next(new ErrorApp(50034)); // la administradora no compra con su cuenta
  }
  next();
}

module.exports = { crearSesion, cerrarSesion, leerSesion, requiereAdmin, requiereCliente };
