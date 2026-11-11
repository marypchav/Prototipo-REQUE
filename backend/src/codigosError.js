/*
Traduce los códigos de error a mensajes para el usuario y a estados HTTP.
Los otros módulos agregan aquí sus códigos, sin repetir números.
*/
const mensajes = {
  // de los SP del catálogo
  50000: 'Ocurrió un error inesperado. Intente de nuevo más tarde.',
  50010: 'Revise las tallas ingresadas.',
  50011: 'Este producto ya no está disponible.',
  // del backend
  50031: 'La ruta solicitada no existe.',
  50032: 'Los datos enviados no tienen un formato válido.',
};

const estadosHttp = {
  404: [50011, 50031],
  500: [50000],
};

function mensajeDe(codigo) {
  return mensajes[codigo] || mensajes[50000];
}

function estadoHttpDe(codigo) {
  for (const [estado, codigos] of Object.entries(estadosHttp)) {
    if (codigos.includes(codigo)) {
      return Number(estado);
    }
  }
  return 400; // cualquier otro: datos inválidos
}

module.exports = { mensajeDe, estadoHttpDe };
