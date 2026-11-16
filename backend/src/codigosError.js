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
  50037: 'No se encontró el comprobante de pago.',

  // módulo Gestión de pedidos
  50040: 'El correo electrónico no tiene un formato válido.',
  50041: 'Este correo ya está registrado. Puede iniciar sesión con él.',
  50042: 'El teléfono debe tener entre 8 y 16 dígitos.',
  50043: 'La contraseña debe tener al menos 8 caracteres.',
  50044: 'La dirección seleccionada no existe.',
  50045: 'La provincia seleccionada no existe.',
  50046: 'La cantidad debe ser un número entero mayor que cero.',
  50047: 'Esta talla está agotada.',
  50048: 'La cantidad supera las existencias disponibles.',
  50049: 'Este producto ya no está en su carrito.',
  50050: 'Su carrito está vacío.',
  50051: 'Seleccione un método de pago y un método de entrega.',
  50052: 'Seleccione una dirección de envío.',
  50053: 'El pago en efectivo está disponible solo para retiro en el taller.',
  50054: 'Adjunte el comprobante de pago de SINPE Móvil.',
  50055: 'Algunos productos ya no están disponibles. Revise su carrito.',
  50056: 'El pedido no existe.',
  50057: 'Ese cambio de estado no está permitido.',
  50058: 'Escriba el motivo.',
  50059: 'La notificación no existe.',
};

const estadosHttp = {
  401: [50020, 50033],
  403: [50034],
  404: [50011, 50031, 50037, 50044, 50049, 50056, 50059],
  409: [50041, 50055, 50057], // chocan con el estado actual de los datos
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
