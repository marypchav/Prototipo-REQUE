/*
Traduce los códigos de error a mensajes para el usuario y a estados HTTP.
La lista con su origen está en database/CodigosError.md.
La ortografía de estos textos se evalúa en la rúbrica: revisarlos bien.

Los otros módulos agregan aquí sus códigos, sin repetir números.
*/
const mensajes = {
  // generales
  50000: 'Ocurrió un error inesperado. Intente de nuevo más tarde.',

  // módulo Catálogo de productos (y compartidos con inventario)
  50010: 'Revise las tallas ingresadas.',
  50011: 'Este producto ya no está disponible.',

  // módulo Gestión de inventario
  50020: 'Correo o contraseña incorrectos.',
  50021: 'Complete todos los campos obligatorios.',
  50022: 'El precio debe ser un número mayor que cero.',
  50023: 'La categoría seleccionada no existe.',
  50024: 'Las cantidades deben ser números enteros, sin decimales, letras ni valores negativos.',
  50025: 'Revise las tallas ingresadas.',
  50026: 'Ingrese existencias en al menos una talla.',
  50027: 'Solo se permiten imágenes PNG o JPG.',

  // del backend
  50031: 'La ruta solicitada no existe.',
  50032: 'Los datos enviados no tienen un formato válido.',
  50033: 'Debe iniciar sesión para continuar.',
  50034: 'No tiene permiso para realizar esta acción.',
  50035: 'La imagen no puede superar los 5 MB.',
  50036: 'Seleccione una imagen.',
};

const estadosHttp = {
  401: [50020, 50033],
  403: [50034],
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
