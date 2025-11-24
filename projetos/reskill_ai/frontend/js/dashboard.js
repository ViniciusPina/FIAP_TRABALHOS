// frontend/js/dashboard.js
// Atualizado para exibir nomes reais e links

const API_BASE = "http://localhost:8080/reskill-backend-1.0-SNAPSHOT/api";

// Função para pegar ID da URL (ex: profile.html?idUsuario=5)
function getUserIdFromQuery() {
    const params = new URLSearchParams(window.location.search);
    const v = params.get("idUsuario");
    if (!v) return 1; // Default para 1 se não tiver na URL
    const n = Number(v);
    return Number.isNaN(n) ? 1 : n;
}

const USER_ID = getUserIdFromQuery();

async function fetchJSON(url) {
    try {
        const resp = await fetch(url);
        if (!resp.ok) return null;
        return await resp.json();
    } catch (e) {
        console.error("Erro API:", url, e);
        return null;
    }
}

async function loadPerfil() {
    const data = await fetchJSON(`${API_BASE}/usuarios/${USER_ID}`);
    const el = document.querySelector("#user-info"); // Ajustado para o ID correto no HTML do profile

    if (!el) return; // Proteção caso elemento não exista

    if (!data) {
        el.innerHTML = `<p class="metric" style="color:#f97373">Usuário #${USER_ID} não encontrado.</p>`;
        return;
    }

    // Renderiza card do usuário
    el.innerHTML = `
        <div style="margin-bottom: 10px;">
            <div class="data-card-title" style="font-size: 20px;">${data.nome}</div>
            <div class="rec-meta" style="margin-top:5px; color: #9ca3af;">
                ${data.areaInteresse} · ${data.nivelFormacao}
            </div>
        </div>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; font-size: 13px; color: #cbd5e1;">
            <div><strong>Idade:</strong> ${data.idade}</div>
            <div><strong>ID:</strong> ${data.idUsuario}</div>
            <div style="grid-column: 1 / -1;">
                <strong>Habilidades:</strong><br>
                <span style="color: #fff;">${data.habilidades}</span>
            </div>
             <div style="grid-column: 1 / -1;">
                <strong>Objetivo:</strong><br>
                <span style="color: #fff;">${data.objetivoProfissional}</span>
            </div>
        </div>
    `;
}

async function loadRecomendacoes() {
    const recs = await fetchJSON(`${API_BASE}/recomendacoes/usuario/${USER_ID}`);
    const el = document.querySelector("#recomendacoes-usuario");

    if (!el) return;

    if (!recs || recs.length === 0) {
        el.innerHTML = `<div style="padding: 20px; text-align: center; border: 1px dashed #374151; border-radius: 12px; color: #9ca3af;">
            Nenhuma recomendação encontrada.<br>
            <small>Execute o script R para gerar.</small>
        </div>`;
        return;
    }

    // Renderiza os cards bonitos (Igual ao App.js)
    el.innerHTML = recs.map(r => {
        // Lógica de Cores
        let scoreColor = "#a855f7"; // Roxo
        if(r.score >= 0.8) scoreColor = "#22c55e"; // Verde
        else if(r.score < 0.5) scoreColor = "#f59e0b"; // Amarelo

        // Fallback para nome se vier vazio (não deve acontecer com o banco novo)
        const nomeCurso = r.nomeCurso || `Curso #${r.idCurso}`;
        const categoria = r.categoriaCurso || "Geral";

        return `
        <div class="rec-card" style="margin-bottom: 10px;">
            <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                <span style="font-size: 10px; background: #1e293b; padding: 2px 8px; border-radius: 4px; color: #94a3b8;">
                    ${categoria}
                </span>
                <span style="font-size: 11px; color: ${scoreColor}; font-weight: bold;">
                    ${(r.score * 100).toFixed(0)}% Match
                </span>
            </div>
            
            <div class="rec-title" style="font-size: 14px; margin-bottom: 4px;">
                ${nomeCurso}
            </div>
            
            <div class="rec-meta">
                Nível: <strong>${r.nivelCurso || "-"}</strong> · 
                ${r.cargaHorariaCurso ? r.cargaHorariaCurso + "h" : ""}
            </div>

            <div class="rec-footer" style="margin-top: 12px; display: flex; justify-content: space-between; align-items: center;">
                 <span class="pill-type" style="font-size: 9px;">${r.tipoRecomendacao}</span>
                 <a href="${r.linkCurso || '#'}" target="_blank" 
                    style="background: ${scoreColor}; color: #000; text-decoration: none; padding: 4px 12px; border-radius: 6px; font-size: 11px; font-weight: bold;">
                    Acessar ↗
                 </a>
            </div>
        </div>
        `;
    }).join("");
}

async function carregarCursosECursosInscritos() {
    // Implementação simplificada para o Dashboard focar nas recomendações
    // Você pode manter a lógica original aqui se quiser listar todos os cursos
    // Mas a prioridade era consertar a visualização das recomendações acima.
    
    const elCatalogo = document.getElementById("cursos-cadastrados");
    if(elCatalogo) {
        const cursos = await fetchJSON(`${API_BASE}/cursos`);
        if(cursos && cursos.length > 0) {
            elCatalogo.innerHTML = `<p class="metric">Total de ${cursos.length} cursos disponíveis no banco.</p>`;
        }
    }
}

// Inicialização
document.addEventListener("DOMContentLoaded", () => {
    loadPerfil();
    loadRecomendacoes();
    carregarCursosECursosInscritos();
    
    // Botões de ação (Mock ou reais, dependendo da sua implementação de delete)
    const btnDel = document.getElementById("btn-deletar-curso");
    if(btnDel) btnDel.addEventListener("click", () => alert("Funcionalidade Admin"));
});