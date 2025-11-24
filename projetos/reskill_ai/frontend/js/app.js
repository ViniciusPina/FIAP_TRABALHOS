// js/app.js (Versão Final - Sem Mock)
const API_BASE = "http://localhost:8080/reskill-backend-1.0-SNAPSHOT/api";

function renderizarRecomendacoes(lista) {
    const container = document.getElementById("recs-list");
    container.innerHTML = "";

    if (!lista || lista.length === 0) {
        container.innerHTML = `<div style="padding: 20px; text-align: center; color: #9ca3af; border: 1px dashed #374151; border-radius: 12px;">Aguardando processamento da IA...</div>`;
        return;
    }

    lista.forEach(rec => {
        const card = document.createElement("div");
        card.className = "rec-card";
        
        let scoreColor = rec.score >= 0.8 ? "#22c55e" : (rec.score >= 0.5 ? "#f59e0b" : "#a855f7");
        let scoreText = (rec.score * 100).toFixed(0) + "%";

        card.innerHTML = `
          <div style="grid-column: 1 / -1; display: flex; justify-content: space-between; margin-bottom: 8px;">
              <span style="font-size: 10px; background: #1e293b; padding: 2px 8px; border-radius: 4px; color: #94a3b8;">${rec.categoriaCurso}</span>
              <span style="font-size: 10px; color: ${scoreColor}; font-weight: bold;">${scoreText} Match</span>
          </div>
          <div style="grid-column: 1 / span 2;">
              <div class="rec-title" style="font-size: 14px; margin-bottom: 4px;">${rec.nomeCurso}</div>
              <div class="rec-meta" style="color: #cbd5e1;">Nível: <strong>${rec.nivelCurso}</strong> · ${rec.cargaHorariaCurso}h</div>
          </div>
          <div class="rec-footer" style="margin-top: 10px;">
              <span class="pill-type" style="text-transform: uppercase; font-size: 9px;">${rec.tipoRecomendacao}</span>
              <a href="${rec.linkCurso}" target="_blank" style="background: ${scoreColor}; color: #000; text-decoration: none; padding: 4px 12px; border-radius: 6px; font-size: 11px; font-weight: bold;">Acessar Curso ↗</a>
          </div>
      `;
        container.appendChild(card);
    });
}

document.addEventListener("DOMContentLoaded", () => {
    const form = document.getElementById("perfil-form");
    const statusLabel = document.getElementById("status-label");

    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const formData = new FormData(form);
        const perfil = Object.fromEntries(formData.entries());

        statusLabel.textContent = "Salvando e Processando IA...";
        statusLabel.style.color = "#e5e7eb";

        try {
            // 1. Salva e Roda IA (Automático no Java)
            const respUser = await fetch(`${API_BASE}/usuarios`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    nome: perfil.nome, idade: Number(perfil.idade),
                    areaInteresse: perfil.area_interesse, nivelFormacao: perfil.nivel_formacao,
                    habilidades: perfil.habilidades, objetivoProfissional: perfil.objetivo_profissional
                })
            });
            
            const userCriado = await respUser.json();
            
            // 2. Busca Recomendações
            const respRecs = await fetch(`${API_BASE}/recomendacoes/usuario/${userCriado.idUsuario}`);
            const recs = await respRecs.json();
            
            renderizarRecomendacoes(recs);
            
            if (recs.length > 0) {
                statusLabel.textContent = `Sucesso! ${recs.length} recomendações encontradas.`;
                statusLabel.style.color = "#22c55e";
            } else {
                statusLabel.textContent = "Aguardando processamento...";
            }

        } catch (err) {
            console.error(err);
            statusLabel.textContent = "Erro no servidor.";
            statusLabel.style.color = "#f97373";
        }
    });
});