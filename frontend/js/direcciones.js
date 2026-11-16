/* =====================================================================
   Direcciones de envío del cliente: /cuenta/direcciones.html
     GP003 Visualizar   GP004 Agregar   GP005 Modificar   GP006 Eliminar
   Con ?volver=/orden.html&nueva=1 abre el formulario de una vez y, al
   guardar, regresa a la orden (GP012 flujo alterno).
   ===================================================================== */

const params = new URLSearchParams(location.search);
const volver = params.get('volver') ? destinoSeguro(params.get('volver'), null) : null;

const el = {
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoDirecciones'),
  lista: document.getElementById('listaDirecciones'),
  avisoVolver: document.getElementById('avisoVolver'),
  agregar: document.getElementById('agregarDireccion'),

  dlg: document.getElementById('dialogoDireccion'),
  form: document.getElementById('formDireccion'),
  titulo: document.getElementById('tituloDireccion'),
  error: document.getElementById('errorDireccion'),
  provincia: document.getElementById('provincia'),
  canton: document.getElementById('canton'),
  distrito: document.getElementById('distrito'),
  otrasSenas: document.getElementById('otrasSenas'),
  guardar: document.getElementById('guardarDireccion'),

  dlgEliminar: document.getElementById('dialogoEliminar'),
  textoEliminar: document.getElementById('textoEliminar'),
  errorEliminar: document.getElementById('errorEliminar'),
  confirmarEliminar: document.getElementById('confirmarEliminar'),
};

let direcciones = [];
let enEdicion = null; // IdDireccion que se modifica, o null si es nueva

function textoDireccion(d) {
  return `${d.OtrasSenas}, ${d.Distrito}, ${d.Canton}, ${d.Provincia}`;
}

/* ---------------- GP003 Visualizar ---------------- */

async function cargar() {
  try {
    const { datos } = await api('/cliente/direcciones');
    direcciones = datos.direcciones ?? [];
    if (el.provincia.options.length <= 1) {
      el.provincia.innerHTML +=
        (datos.provincias ?? []).map((p) => `<option value="${p.IdProvincia}">${escapar(p.Nombre)}</option>`).join('');
    }
    pintar();
  } catch (error) {
    if (error.codigo === 50033) return;
    el.estado.innerHTML = `<p class="mensaje mensaje-error">${escapar(error.message)}</p>`;
  } finally {
    el.cargando.hidden = true;
  }
}

function pintar() {
  if (!direcciones.length) {
    el.lista.replaceChildren();
    el.estado.innerHTML = `
      <div class="vacio">
        <img class="monograma" src="/img/monograma.svg" alt="">
        <h2>Aún no tiene direcciones registradas</h2>
        <p>Agregue una para recibir sus pedidos por envío.</p>
      </div>`;
    return;
  }
  el.estado.innerHTML = '';
  el.lista.innerHTML = direcciones
    .map(
      (d) => `
      <li class="tarjeta-direccion" data-id="${d.IdDireccion}">
        <div>
          <h2>${escapar(d.Provincia)}</h2>
          <p>${escapar(d.Canton)}, ${escapar(d.Distrito)}</p>
          <p class="senas">${escapar(d.OtrasSenas)}</p>
        </div>
        <div class="fila-acciones">
          <button type="button" class="boton boton-secundario boton-pequeno" data-accion="modificar">Modificar</button>
          <button type="button" class="boton boton-texto boton-pequeno" data-accion="eliminar">Eliminar</button>
        </div>
      </li>`
    )
    .join('');
}

/* ---------------- GP004 Agregar y GP005 Modificar ---------------- */

function abrirFormulario(direccion = null) {
  enEdicion = direccion?.IdDireccion ?? null;
  el.titulo.textContent = direccion ? 'Modificar dirección' : 'Agregar dirección';
  el.provincia.value = direccion ? String(direccion.IdProvincia) : '';
  el.canton.value = direccion?.Canton ?? '';
  el.distrito.value = direccion?.Distrito ?? '';
  el.otrasSenas.value = direccion?.OtrasSenas ?? '';
  el.error.hidden = true;
  el.form.querySelectorAll('[aria-invalid]').forEach((c) => c.removeAttribute('aria-invalid'));
  el.dlg.showModal();
  el.provincia.focus();
}

el.agregar.addEventListener('click', () => abrirFormulario());

el.form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  el.error.hidden = true;
  el.form.querySelectorAll('[aria-invalid]').forEach((c) => c.removeAttribute('aria-invalid'));

  // GP004 flujo alterno: ningún campo vacío
  const vacio = [el.provincia, el.canton, el.distrito, el.otrasSenas].find((c) => !c.value.trim());
  if (vacio) {
    el.error.textContent = 'Complete todos los campos obligatorios.';
    el.error.hidden = false;
    vacio.setAttribute('aria-invalid', 'true');
    vacio.focus();
    return;
  }

  const cuerpo = {
    idProvincia: Number(el.provincia.value),
    canton: el.canton.value.trim(),
    distrito: el.distrito.value.trim(),
    otrasSenas: el.otrasSenas.value.trim(),
  };

  el.guardar.disabled = true;
  try {
    const { mensaje } = enEdicion
      ? await api('/cliente/direcciones/' + enEdicion, { metodo: 'PUT', cuerpo })
      : await api('/cliente/direcciones', { metodo: 'POST', cuerpo });

    el.dlg.close();

    // venía de la orden: regresa a la selección (GP012 flujo alterno)
    if (volver && !enEdicion) {
      avisarEnSiguientePagina(mensaje);
      location.assign(volver);
      return;
    }
    notificar(mensaje);
    cargar();
  } catch (error) {
    el.error.textContent = error.message;
    el.error.hidden = false;
  } finally {
    el.guardar.disabled = false;
  }
});

/* ---------------- GP006 Eliminar ---------------- */

let porEliminar = null;

el.lista.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-accion]');
  if (!boton) return;
  const id = Number(boton.closest('[data-id]').dataset.id);
  const direccion = direcciones.find((d) => d.IdDireccion === id);
  if (!direccion) return;

  if (boton.dataset.accion === 'modificar') abrirFormulario(direccion);
  if (boton.dataset.accion === 'eliminar') {
    porEliminar = direccion;
    el.textoEliminar.textContent = textoDireccion(direccion);
    el.errorEliminar.hidden = true;
    el.dlgEliminar.showModal(); // "¿Confirma que desea eliminar esta dirección?"
  }
});

el.confirmarEliminar.addEventListener('click', async () => {
  el.confirmarEliminar.disabled = true;
  try {
    const { mensaje } = await api('/cliente/direcciones/' + porEliminar.IdDireccion, { metodo: 'DELETE' });
    el.dlgEliminar.close();
    notificar(mensaje);
    cargar();
  } catch (error) {
    el.errorEliminar.textContent = error.message;
    el.errorEliminar.hidden = false;
  } finally {
    el.confirmarEliminar.disabled = false;
  }
});

/* ---------------- Inicio ---------------- */

(async () => {
  if (!(await exigirCliente('direcciones'))) return;

  if (volver) {
    el.avisoVolver.innerHTML = `Al guardar la dirección regresará a su orden. <a href="${escapar(volver)}">Volver sin agregar</a>`;
    el.avisoVolver.hidden = false;
  }

  await cargar();
  if (params.get('nueva') === '1') abrirFormulario();
})();
