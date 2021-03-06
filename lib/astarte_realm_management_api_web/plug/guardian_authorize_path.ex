#
# This file is part of Astarte.
#
# Astarte is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Astarte is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Astarte.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright (C) 2018 Ispirata Srl
#

defmodule Astarte.RealmManagement.APIWeb.Plug.GuardianAuthorizePath do
  use Plug.Builder

  import Plug.Conn

  require Logger

  alias Astarte.RealmManagement.API.Auth.User
  alias Astarte.RealmManagement.APIWeb.AuthGuardian
  alias Astarte.RealmManagement.APIWeb.FallbackController

  plug Guardian.Plug.Pipeline,
    otp_app: :astarte_realm_management_api,
    module: Astarte.RealmManagement.APIWeb.AuthGuardian,
    error_handler: FallbackController
  plug Astarte.RealmManagement.APIWeb.Plug.VerifyHeader
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
  plug :authorize

  defp authorize(conn, opts) do
    with %User{authorizations: authorizations} <- AuthGuardian.Plug.current_resource(conn),
         {:ok, auth_path} <- build_auth_path(conn),
         :ok <- is_path_authorized?(conn.method, auth_path, authorizations) do
      conn
    else
      {:error, :invalid_auth_path} ->
        Logger.warn(
          "Can't build auth_path with path_params: #{inspect(conn.path_params)} path_info: #{
            inspect(conn.path_info)
          } query_params: #{inspect(conn.query_params)}"
        )

        conn
        |> FallbackController.auth_error({:unauthorized, :invalid_auth_path}, opts)
        |> halt()

      {:error, {:unauthorized, method, auth_path, authorizations}} ->
        Logger.info(
          "Unauthorized request: #{method} #{auth_path} failed with authorizations #{
            inspect(authorizations)
          }"
        )

        conn
        |> FallbackController.auth_error({:unauthorized, :authorization_path_not_matched}, opts)
        |> halt()
    end
  end

  defp build_auth_path(conn) do
    with %{"realm_name" => realm} <- conn.path_params,
         [^realm | rest] <- Enum.drop_while(conn.path_info, fn token -> token != realm end) do
      {:ok, Enum.join(rest, "/")}
    else
      _ ->
        {:error, :invalid_auth_path}
    end
  end

  defp is_path_authorized?(method, auth_path, authorizations) when is_list(authorizations) do
    authorized =
      Enum.any?(authorizations, fn auth_string ->
        case get_auth_regex(auth_string) do
          {:ok, {method_regex, path_regex}} ->
            Regex.match?(method_regex, method) and Regex.match?(path_regex, auth_path)

          _ ->
            false
        end
      end)

    if authorized do
      :ok
    else
      {:error, {:unauthorized, method, auth_path, authorizations}}
    end
  end

  defp is_path_authorized?(method, auth_path, authorizations),
    do: {:error, {:unauthorized, method, auth_path, authorizations}}

  defp get_auth_regex(authorization_string) do
    # TODO: right now regex have to be terminated with $ manually, otherwise they also match prefix.
    # We can think about always terminating them here appending a $ to the string
    with [method_auth, _opts, path_auth] <- String.split(authorization_string, ":", parts: 3),
         {:ok, method_regex} <- Regex.compile(method_auth),
         {:ok, path_regex} <- Regex.compile(path_auth) do
      {:ok, {method_regex, path_regex}}
    else
      [] ->
        {:error, :invalid_authorization_string}

      _ ->
        {:error, :invalid_regex}
    end
  end
end
