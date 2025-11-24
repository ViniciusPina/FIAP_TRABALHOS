package br.com.asteria.reskill.controller;

import br.com.asteria.reskill.entity.Usuario;
import br.com.asteria.reskill.service.UsuarioService;

import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.sql.SQLException;
import java.util.List;

@Path("/usuarios")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class UsuarioController {

    private final UsuarioService service = new UsuarioService();
    private static final String VARIAVEL_AMBIENTE = "RESKILL_HOME";
    private static final String CAMINHO_RELATIVO_SCRIPT = "/backend/analysis/recommender_reskill.R";

    @POST
    public Response criar(Usuario usuario) {
        try {
            Usuario criado = service.criar(usuario);
            System.out.println("✅ Usuário salvo. ID: " + criado.getIdUsuario());
            executarScriptR(); // Automação
            return Response.status(Response.Status.CREATED).entity(criado).build();
        } catch (Exception e) {
            return Response.serverError().entity("Erro: " + e.getMessage()).build();
        }
    }

    private void executarScriptR() {
        try {
            String projetoHome = System.getenv(VARIAVEL_AMBIENTE);
            if (projetoHome == null) {
                System.err.println("❌ Variável RESKILL_HOME não encontrada!");
                return;
            }
            String caminhoScript = projetoHome + CAMINHO_RELATIVO_SCRIPT;
            ProcessBuilder pb = new ProcessBuilder("Rscript", caminhoScript);
            pb.start().waitFor();
            System.out.println("✅ IA executada.");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
    
    // ... métodos GET buscarPorId e listar ...
    @GET
    @Path("/{id}")
    public Response buscarPorId(@PathParam("id") Long id) {
        try {
            return Response.ok(service.buscarPorId(id)).build();
        } catch (SQLException e) { return Response.serverError().build(); }
    }
}