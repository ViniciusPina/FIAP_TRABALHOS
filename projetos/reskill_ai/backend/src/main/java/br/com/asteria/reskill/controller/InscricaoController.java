package br.com.asteria.reskill.controller;

import br.com.asteria.reskill.entity.Inscricao;
import br.com.asteria.reskill.service.InscricaoService;

import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.sql.SQLException;
import java.util.List;

@Path("/inscricoes")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class InscricaoController {

    private final InscricaoService service = new InscricaoService();

    @POST
    public Response criar(Inscricao i) {
        try {
            Inscricao criada = service.criar(i);
            return Response.status(Response.Status.CREATED).entity(criada).build();
        } catch (SQLException e) {
            return Response.serverError().entity(e.getMessage()).build();
        }
    }

    @GET
    @Path("/usuario/{idUsuario}")
    public Response listarPorUsuario(@PathParam("idUsuario") Long idUsuario) {
        try {
            List<Inscricao> lista = service.listarPorUsuario(idUsuario);
            return Response.ok(lista).build();
        } catch (SQLException e) {
            return Response.serverError().entity(e.getMessage()).build();
        }
    }
}
