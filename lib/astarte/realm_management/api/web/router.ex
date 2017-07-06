defmodule Astarte.RealmManagement.API.Web.Router do
  use Astarte.RealmManagement.API.Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", Astarte.RealmManagement.API.Web do
    pipe_through :api
  end
end
