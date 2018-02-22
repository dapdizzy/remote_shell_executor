defmodule RemoteShellExecutor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Supervisor.Spec

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      worker(
        RabbitMQReceiver,
        [
          [],
          nil,
          RemoteShellExecutor,
          :process_request,
          true,
          [name: RabbitMQReceiver],
          [exchange: "topic_exchange", exchange_type: :topic, binding_keys: ["mow04dev014", "lips.dev.aos.dap"], rpc_mode: true]
        ]),
      worker(
        RabbitMQSender,
        [
          [],
          [name: RabbitMQSender]
          # [exchange: "topic_exchange", exchange_type: :topic, rpc_mode: true]
        ]
      )
      # Starts a worker by calling: RemoteShellExecutor.Worker.start_link(arg)
      # {RemoteShellExecutor.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RemoteShellExecutor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
