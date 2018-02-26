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

  defp try_process_service_command(command) do
    do_process_command(
      command,
      ~r/execute\s+service\s+(?<action>watch|unwatch|pause|resume)\s+(?<args[\w\_\-\"\'\`\. ]+)/miU,
      fn -> :ok end,
      nil
      )
  end

  defp do_process_command(command, regex, action, default_result \\ nil) do
    regex |> Regex.named_captures(command)
      |> case do
        nil -> default_result
        %{} = map -> map -> map |> action.()
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
      (rex = ~r/\"([\w\W]*)\"/miU)
      |> Regex.scan(args, capture: :all_but_first)
      |> case do
        list ->
          updated_args =
            unless list |> Enum.empty? do
              rex |> replace_quoted_args(args) # Regex.replace(args, "")
            else
              args
            end
          {list |> List.flatten, updated_args}
      end
    # IO.puts "quoted_qrgs_list: #{inspect quoted_args_list}, next_args: #{next_args}"
    single_args_list = ~r/\s/ |> Regex.split(next_args, trim: true)
    # Replace dummy "replacement_[num]" args in the list witheir counterparts from quoted_args_list (by number).
    for arg <- single_args_list do
      r = ~r/^replacement_(?<number>\d+)$/miU
      r |> Regex.named_captures(arg)
      |> case do
        nil -> arg
        %{"number" => number} ->
          quoted_args_list |> Enum.at(number |> String.to_integer)
      end
    end
    # IO.puts "Quoted args: #{inspect quoted_args_list}, single args: #{inspect single_args_list}"
    # quoted_args_list ++ single_args_list
  end

  defp replace_quoted_args(rex, string) do
    # Start a 'local' agent to hold the ordinal num of the replacement.
    {:ok, pid} = Agent.start_link(fn -> 0 end)
    get_next_num = fn -> pid |> Agent.get_and_update(fn counter -> {counter, counter + 1} end) end
    replaced_string = rex |> Regex.replace(string, fn _, _ -> "replacement_#{get_next_num.()}" end)
    pid |> Agent.stop
    replaced_string
  end

end
