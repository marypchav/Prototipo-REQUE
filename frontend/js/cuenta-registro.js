/* =====================================================================
   GP001 Registrar cliente: /cuenta/registrarse.html
   Al crear la cuenta muestra la confirmación y lleva a iniciar sesión.
   ===================================================================== */

const form = document.getElementById('formRegistro');
const campos = {
  nombre: document.getElementById('nombre'),
  correo: document.getElementById('correo'),
  telefono: document.getElementById('telefono'),
  contrasena: document.getElementById('contrasena'),
};
const errorRegistro = document.getElementById('errorRegistro');
const botonRegistrar = document.getElementById('botonRegistrar');

const volver = destinoSeguro(new URLSearchParams(location.search).get('volver'), '/');
const urlIngreso = '/cuenta/ingresar.html?volver=' + encodeURIComponent(volver);
document.getElementById('enlaceIngreso').href = urlIngreso;

const CORREO_VALIDO = /^[^\s@,;:<>()]+@[^\s@,;:<>()]+\.[^\s@,;:<>()]+$/;

// GP001 flujo alterno 3: se indica el error para que lo corrija
function mostrarError(texto, campo, { conEnlaceIngreso = false } = {}) {
  errorRegistro.innerHTML = escapar(texto) + (conEnlaceIngreso ? ` <a href="${urlIngreso}">Iniciar sesión</a>` : '');
  errorRegistro.hidden = false;
  if (campo) {
    campo.setAttribute('aria-invalid', 'true');
    campo.focus();
  }
}

function validar() {
  Object.values(campos).forEach((c) => c.removeAttribute('aria-invalid'));
  errorRegistro.hidden = true;

  const vacio = Object.values(campos).find((c) => !c.value.trim());
  if (vacio) return mostrarError('Complete todos los campos obligatorios.', vacio), false;

  if (!CORREO_VALIDO.test(campos.correo.value.trim())) {
    return mostrarError('El correo electrónico no tiene un formato válido.', campos.correo), false;
  }

  const digitos = campos.telefono.value.replace(/[\s-]/g, '');
  if (!/^\+?\d{8,16}$/.test(digitos)) {
    return mostrarError('El teléfono debe tener entre 8 y 16 dígitos.', campos.telefono), false;
  }

  if (campos.contrasena.value.length < 8) {
    return mostrarError('La contraseña debe tener al menos 8 caracteres.', campos.contrasena), false;
  }

  return true;
}

form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  if (!validar()) return;

  botonRegistrar.disabled = true;
  botonRegistrar.textContent = 'Creando cuenta…';

  try {
    const { mensaje } = await api('/clientes', {
      metodo: 'POST',
      cuerpo: {
        nombre: campos.nombre.value.trim(),
        correo: campos.correo.value.trim(),
        telefono: campos.telefono.value.trim(),
        contrasena: campos.contrasena.value,
      },
    });

    // GP001 paso 4.3: confirmación y a la pantalla de inicio de sesión
    avisarEnSiguientePagina(mensaje);
    guardarTemporal('correoRegistrado', campos.correo.value.trim().toLowerCase());
    location.assign(urlIngreso);
  } catch (error) {
    const campoDelError = { 50040: campos.correo, 50041: campos.correo, 50042: campos.telefono, 50043: campos.contrasena };
    // GP001 flujo alterno 4: correo ya registrado, se ofrece iniciar sesión
    mostrarError(error.message, campoDelError[error.codigo], { conEnlaceIngreso: error.codigo === 50041 });
    botonRegistrar.disabled = false;
    botonRegistrar.textContent = 'Crear cuenta';
  }
});

pintarEncabezadoPublico('ingresar');
pintarPie();
campos.nombre.focus();
