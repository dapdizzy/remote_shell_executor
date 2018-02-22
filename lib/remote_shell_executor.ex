defmodule RemoteShellExecutor do
  @moduledoc """
  Documentation for RemoteShellExecutor.
  """

  @doc """
  Hello world.

  ## Examples

      iex> RemoteShellExecutor.hello
      :world

  """
  def hello do
    :world
  end

  def process_request(%ReceiverMessage{payload: payload, correlation_id: correlation_id, reply_to: reply_queue}) do
    response = try_process_request payload
    IO.puts "Response is #{response}"
    RabbitMQSender |> RabbitMQSender.send_message(reply_queue, response, false, correlation_id: correlation_id)
  end

  defp try_process_request(request) do
    ~r/execute\s+(?<script_name>[\w_\.\-\"\']+)(?<args>[\w\s\_\-\.\"\']*)?/miu
      |> Regex.named_captures(request)
      |> case do
        nil -> "Could not process your request"
        %{"script_name" => script_name} = map ->
          args = map["args"]
          args_list = args |> parse_args
            # (if args, do: ~r/\s/ |> Regex.split(args, trim: true), else: [])
          # Now we can try to call the script if one exists in our scripts_dir folder.
          scripts_dir = Application.get_env(:remote_shell_executor, :scripts_dir)
          unless scripts_dir, do: raise "Scripts dir is not configured"
          full_script_name = script_name <> ".ps1"
          path = scripts_dir |> Path.join(full_script_name)
          result =
            if path |> File.exists? do
              # Execute the script
              exec_name = ".\\" <> full_script_name
              ShellExecutor.execute "powershell", exec_name, args_list, extract_last_line: true, working_directory: scripts_dir
            else
              "Script #{full_script_name} does not exist in the #{scripts_dir}"
            end
          result
      end
  end

  # def start(_start_type, _start_args) do
  #   children = [
  #     worker(RabbitMQReceiver, [[], nil, RemoteShellExecutor, :some_method])
  #     # Starts a worker by calling: RemoteShellExecutor.Worker.start_link(arg)
  #     # {RemoteShellExecutor.Worker, arg},
  #   ]
  #
  #   # See https://hexdocs.pm/elixir/Supervisor.html
  #   # for other strategies and supported options
  #   opts = [strategy: :one_for_one, name: RemoteShellExecutor.Supervisor]
  #   Supervisor.start_link(children, opts)
  # end

  def parse_args(args) do
    {quoted_args_list, next_args} =
      (rex = ~r/\"([\w\W]*)\"/mui)
      |> Regex.scan(args, capture: :all_but_first)
      |> case do
        list ->
          updated_args =
            unless list |> Enum.empty? do
              rex |> Regex.replace(args, "")
            else
              args
            end
          {list |> List.flatten, updated_args}
      end
    single_args_list = ~r/\s/ |> Regex.split(next_args, trim: true)
    # IO.puts "Quoted args: #{inspect quoted_args_list}, single args: #{inspect single_args_list}"
    quoted_args_list ++ single_args_list
  end

end
