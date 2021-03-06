defmodule Farmbot.Serial.Handler.OpenTTY do
  @moduledoc false
  alias Nerves.UART
  alias Farmbot.Serial.Handler
  use Farmbot.DebugLog
  import Supervisor.Spec

  @baud 115_200

  defp ensure_supervisor(sup) when is_atom(sup) do
    case Process.whereis(sup) do
      pid when is_pid(pid) -> ensure_supervisor(pid)
      _ -> ensure_supervisor(sup)
    end
  end

  defp ensure_supervisor(sup) when is_pid(sup) do
    if Process.alive?(sup), do: :ok, else: ensure_supervisor(sup)
  end

  if Mix.Project.config[:target] != "host" do

    # if runnin on the device, enumerate any uart devices and open them
    # individually.
    @spec open_ttys(atom | pid, [binary]) :: :ok | no_return
    def open_ttys(supervisor, ttys \\ nil) do
      ensure_supervisor(supervisor)
      blah = ttys || UART.enumerate() |> Map.drop(["ttyS0","ttyAMA0"]) |> Map.keys
      case blah do
        [one_tty] ->
          thing = {one_tty, [name: Farmbot.Serial.Handler]}
          try_open([thing], supervisor)
        ttys when is_list(ttys) ->
          ttys
          |> Enum.map(fn(device) -> {device, []} end)
          |> try_open(supervisor)
      end
    end
  else

    # If running in the host environment the proper tty is expected to be in
    # the environment
    defp get_tty do
      case Application.get_env(:farmbot, :tty) do
        {:system, env} -> System.get_env(env)
        tty when is_binary(tty) -> tty
        _ -> nil
      end
    end

    @spec open_ttys(atom | pid, [binary]) :: :ok | no_return
    def open_ttys(supervisor, list \\ nil)
    def open_ttys(supervisor, _) do
      ensure_supervisor(supervisor)
      if get_tty() do
        thing = {get_tty(), [name: Farmbot.Serial.Handler]}
        try_open([thing], supervisor)
      else
        debug_log ">> Please export ARDUINO_TTY in your environment"
        :ok
      end
    end

  end

  @spec try_open([{binary, [any]}], atom | pid) :: :ok | no_return
  defp try_open([], _), do: :ok
  defp try_open([{tty, opts} | rest], sup) do
    {:ok, nerves} = UART.start_link()
    nerves
    |> UART.open(tty, speed: @baud, active: false)
    |> supervise_process({tty, opts}, sup, nerves)

    try_open(rest, sup)
  end

  @spec supervise_process(any, binary, atom | pid, atom | pid)
    :: {:ok, pid} | false | no_return
  defp supervise_process(:ok, {tty, opts}, sup, nerves) do
    worker_spec = worker(Handler, [nerves, tty, opts], [restart: :permanent])
    UART.close(nerves)
    Process.sleep(1500)
    {:ok, _pid} = Supervisor.start_child(sup, worker_spec)
  end

  defp supervise_process(resp, {tty, _opts}, _, nerves) do
    GenServer.stop(nerves, :normal)
    raise "Could not open #{tty}: #{inspect resp}"
    false
  end
end
