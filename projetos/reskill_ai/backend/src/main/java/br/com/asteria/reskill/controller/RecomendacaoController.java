package br.com.asteria.reskill.controller;

import br.com.asteria.reskill.entity.Recomendacao;
import br.com.asteria.reskill.service.RecomendacaoService;

import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.sql.SQLException;
import java.util.List;

@Path("/recomendacoes")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class RecomendacaoController {

    private final RecomendacaoService service = new RecomendacaoService();

    @GET
    @Path("/usuario/{idUsuario}")
    public Response listarPorUsuario(@PathParam("idUsuario") Long idUsuario) {
        try {
            List<Recomendacao> lista = service.listarPorUsuario(idUsuario);
            return Response.ok(lista).build();
        } catch (SQLException e) {
            return Response.serverError().entity(e.getMessage()).build();
        }
    }
}
