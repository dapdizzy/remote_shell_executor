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

  defp try_process_command_chained(command, processors, default_result) do
    (processors |> Enum.reduce_while(command, &(wrap_processor(&1).(&2)))) || default_result
  end

  defp wrap_processor(processor) do
    fn arg ->
      IO.puts "Probing processor #{inspect processor}"
      case processor.(arg) do
        nil ->
          IO.puts "got nil result, continue with #{arg}"
          {:cont, arg}
        x ->
          IO.puts "Got #{inspect x} result. Halt."
          {:halt, x}
      end
    end
  end

  def process_request(%ReceiverMessage{payload: payload, correlation_id: correlation_id, reply_to: reply_queue}) do
    IO.puts "Payload arrived: #{payload}"
    response = try_process_command_chained payload, [&try_process_service_command/1, &try_process_request/1], "Could not process your request"
    # response = try_process_request payload
    IO.puts "Response is #{response}"
    ReplySender |> RabbitMQSender.send_message(reply_queue, response, false, correlation_id: correlation_id)
  end

  defp try_process_request(request) do
    ~r/execute\s+(?<script_name>[\w_\.\-\"\']+)(?<args>[\w\s\_\-\.\"\']*)?/mi
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
      ~r/execute\s+service\s+(?<action>(watch|unwatch|pause|resume))\s+(?<arg>[\w\_\-\"\'\`\.\s]*)/mi,
      &try_execute_service_command/2,
      nil
      )
  end

  defp do_process_command(command, regex, action, default_result \\ nil) do
    IO.puts "Probing regex #{inspect regex}"
    regex |> Regex.named_captures(command)
      |> case do
        nil ->
          IO.puts "Regex failed"
          default_result
        %{} = map ->
          IO.puts "Regex succeeded"
          map |> action.(default_result)
      end
  end

  defp try_execute_service_command(captures_map, default_result) do
    IO.puts "Trying to execute service command with captures map: #{inspect captures_map}"
    case captures_map do
      %{"action" => action, "arg" => args} ->
        service_name_regex = ~r/^\s*(?<service_name>([\w\_\-\.]+|\"[\w\W]*\"))\s*$/miU
        case action |> String.downcase do
          "watch" ->
            service_name_regex
              |> Regex.named_captures(args)
              |> case do
                %{"service_name" => service_name} ->
                  service_named_escaed = service_name |> String.replace("\"", "\`")
                  Service.Watcher.add_service service_named_escaed, :on # Lets say the dafault intention to watch service to be on (sounds sane).
                  "Watching service #{service_named_escaed} to be on"
                _ ->
                  "Could not parse service name. Service name should be wither a continuous string or it should be wrapepd in \"double quotes\""
              end
          "unwatch" ->
            service_name = extract_single_capture service_name_regex, args, "service_name"
            if service_name do
              service_named_escaed = service_name |> String.replace("\"", "\`")
              Service.Watcher.stop_watching service_named_escaed
              "Removed service #{service_named_escaed} from the list of services to watch"
            end
          "pause" ->
            cond do
              "all" == args |> String.trim |> String.downcase ->
                Service.Watcher.pause_all
                "All service watch jobs are now freezed"
              (service_name = extract_single_capture service_name_regex, args, "service_name") != nil ->
                service_named_escaed = service_name |> String.replace("\"", "\`")
                Service.Watcher.pause service_named_escaed
                "Watching service #{service_named_escaed} was freezed"
              true -> "Could not parse service name. You could eitehr use `all` or specify a service name as a monolith string or surround it in \"double quotes\"."
            end
          "resume" ->
            cond do
              "all" == args |> String.trim |> String.downcase ->
                Service.Watcher.resume_all
                "All service watch jobs are now resumed (and active again)."
              (service_name = extract_single_capture service_name_regex, args, "service_name") != nil ->
                service_named_escaed = service_name |> String.replace("\"", "\`")
                Service.Watcher.resume service_named_escaed
                "Watching service #{service_named_escaed} was resumed (and is active again)."
              true -> "Could not parse service name. You could eitehr use `all` or specify a service name as a monolith string or surround it in \"double quotes\"."
            end
          _ -> "Invalid service command. Valid commands include: watch, unwatch, pause, resume."
        end
      _ -> default_result
    end
  end

  defp extract_single_capture(regex, string, capture_name, default_value \\ nil) do
    case regex |> Regex.named_captures(string) do
      %{^capture_name => capture_value} -> capture_value
      _ -> default_value
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
