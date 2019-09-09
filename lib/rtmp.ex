defmodule Rtmp.Application do
  @moduledoc """
    Start all the services needed for the RTMP module
  """

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Rtmp.Worker.start_link(arg)
      # {Rtmp.Worker, arg},
    ]

    opts = [strategy: :one_for_one, name: Rtmp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
