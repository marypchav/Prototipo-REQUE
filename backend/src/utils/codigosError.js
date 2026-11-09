/*
Traduce los códigos de error a mensajes para el usuario y a estados HTTP.
Del 50000 al 50027 vienen de los SP (ver database/CodigosError.md).
Del 50028 en adelante los genera el backend.
La ortografía de estos textos se evalúa en la rúbrica: revisarlos bien.
*/
const mensajes = {
  50000: 'Ocurrió un error inesperado. Intente de nuevo más tarde.',
  50001: 'Correo o contraseña incorrectos.',
  50002: 'No tiene permiso para realizar esta acción.',
  50003: 'Complete todos los campos obligatorios.',
  50004: 'Ingrese un correo electrónico válido.',
  50005: 'Este correo ya está registrado. ¿Desea iniciar sesión?',
  50006: 'El teléfono debe tener 8 dígitos.',
  50007: 'Seleccione una categoría válida.',
  50008: 'El precio debe ser mayor que cero.',
  50009: 'La cantidad debe ser un número entero válido.',
  50010: 'Revise las tallas ingresadas.',
  50011: 'Este producto ya no está disponible.',
  50012: 'Solo se permiten imágenes PNG o JPG.',
  50013: 'Seleccione una provincia válida.',
  50014: 'La dirección no existe.',
  50015: 'Este producto ya no está disponible.',
  50016: 'No hay suficientes unidades disponibles.',
  50017: 'Su carrito está vacío.',
  50018: 'El producto ya no está en su carrito.',
  50019: 'Seleccione un método de pago.',
  50020: 'Seleccione un método de entrega.',
  50021: 'El pago en efectivo está disponible solo para retiro en el taller.',
  50022: 'Seleccione una dirección de envío.',
  50023: 'Adjunte el comprobante de pago.',
  50024: 'El pedido no existe.',
  50025: 'No se puede pasar el pedido a ese estado.',
  50026: 'Indique el motivo del rechazo o la cancelación.',
  50027: 'La notificación no existe o ya fue enviada.',
  // generados por el backend
  50028: 'La contraseña debe tener al menos 8 caracteres.',
  50029: 'La imagen no puede superar los 5 MB.',
  50030: 'Debe iniciar sesión para continuar.',
  50031: 'La ruta solicitada no existe.',
  50032: 'Los datos enviados no tienen un formato válido.',
};

const estadosHttp = {
  401: [50001, 50030],
  403: [50002],
  404: [50011, 50014, 50015, 50018, 50024, 50027, 50031],
  409: [50005, 50016, 50025],
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
