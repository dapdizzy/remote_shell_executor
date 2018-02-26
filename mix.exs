defmodule RemoteShellExecutor.Mixfile do
  use Mix.Project

  def project do
    [
      app: :remote_shell_executor,
      version: "0.1.1",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "remote_shell_executor"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RemoteShellExecutor.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rabbitmq_receiver, "~> 0.1.5"},
      {:rabbitmq_sender, "~> 0.1.8"},
      {:shell_executor, "~> 0.1.5"},
      {:ex_doc, ">= 0.0.0", only: :dev}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end

  defp description do
    """
    This is a GenServer-ish implementation of a remote shell execution agent.
    A process that waits for the message to arrive on the RabbitMQ queue, tries to process (via shell execute) the request and send response back via RabbitMQ queue.
    """
  end

  defp package do
    [
      name: "remote_shell_executor",
      maintainers: ["Dmitry A. Pyatkov"],
      licenses: ["Apache 2.0"],
      files: ["lib", "mix.exs"],
      links: %{"HexDocs.pm" => "https://hexdocs.pm"}
    ]
  end
end
