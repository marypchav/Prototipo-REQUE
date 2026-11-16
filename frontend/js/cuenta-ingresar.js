/* =====================================================================
   GP002 Iniciar sesión del cliente: /cuenta/ingresar.html?volver=/producto.html?id=1
   Si el acceso es exitoso, regresa a la página desde la que se pidió
   (GP002 paso 4.2, GP007 flujo alterno 1) o al catálogo.
   ===================================================================== */

const form = document.getElementById('formIngreso');
const correo = document.getElementById('correo');
const contrasena = document.getElementById('contrasena');
const errorIngreso = document.getElementById('errorIngreso');
const botonIngresar = document.getElementById('botonIngresar');

const volver = destinoSeguro(new URLSearchParams(location.search).get('volver'), '/');
const destino = volver.startsWith('/admin/') || volver.startsWith('/cuenta/ingresar') ? '/' : volver;

// el enlace a "Registrarse" conserva a dónde volver
document.getElementById('enlaceRegistro').href = '/cuenta/registrarse.html?volver=' + encodeURIComponent(destino);

function mostrarError(texto) {
  errorIngreso.textContent = texto;
  errorIngreso.hidden = false;
}

form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  errorIngreso.hidden = true;
  [correo, contrasena].forEach((c) => c.removeAttribute('aria-invalid'));

  const vacios = [correo, contrasena].filter((c) => !c.value.trim());
  if (vacios.length) {
    vacios.forEach((c) => c.setAttribute('aria-invalid', 'true'));
    mostrarError('Complete todos los campos obligatorios.');
    vacios[0].focus();
    return;
  }

  botonIngresar.disabled = true;
  botonIngresar.textContent = 'Iniciando sesión…';

  try {
    await api('/clientes/sesion', {
      metodo: 'POST',
      cuerpo: { correo: correo.value.trim(), contrasena: contrasena.value },
    });
    location.replace(destino);
  } catch (error) {
    // GP002 flujo alterno: el mismo mensaje, sin decir cuál dato falló
    mostrarError(error.message);
    contrasena.value = '';
    contrasena.focus();
    botonIngresar.disabled = false;
    botonIngresar.textContent = 'Iniciar sesión';
  }
});

(async () => {
  pintarEncabezadoPublico('ingresar');
  pintarPie();

  // viene de crear su cuenta: mensaje de confirmación y su correo ya escrito (GP001 paso 4.3)
  mostrarAvisoPendiente();
  const correoNuevo = leerTemporal('correoRegistrado', { borrar: true });
  if (correoNuevo) {
    correo.value = correoNuevo;
    contrasena.focus();
  } else {
    correo.focus();
  }

  // si ya tiene la sesión de cliente abierta, pasa directo
  const usuario = await obtenerSesion();
  if (usuario && !usuario.esAdministrador) location.replace(destino);
})();
