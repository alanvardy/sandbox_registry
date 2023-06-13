defmodule SandboxRegistry do
  @moduledoc """
  #{File.read!("./README.md")}

  Registers a map of state per test process, allowing us to build mock functionality on top

  ## Usage

  1. Start the registry in your `test_helper.exs`

  ```elixir
  Registry.start_link(keys: :duplicate, name: :some_registry)
  ```

  `:keys` can be `:duplicate` or `:unique` (duplicate is faster, but you will overwrite state if setting it more than once)
   And the name/keys variables will need to be used in the following functions.

  2. Set the state in a setup block or within the test itself

  ```elixir
  SandboxRegistry.register(:some_registry, :my_context, %{key1: "value", key2: "other_value"}, :duplicate)
  ```

  3. Access the state from anywhere in the application. SandboxRegistry functions are not available outside of test.

  ```elixir
  if Mix.env() === :test do
    def get_cache_value(key)
    :some_registry
    |> SandboxRegistry.lookup(:my_context)
    |> Map.fetch!(key)
  else
    defdelegate get_cache_value(key), to: RealProductionCache
  end
  ```
  """

  @type registry :: atom
  @type context :: atom | String.t()
  @type state :: map
  @type keys :: :duplicate | :unique
  @type result :: {:error, :pid_not_registered | :registry_not_started} | {:ok, map}

  @sleep 10

  @doc """
  Registers a map of state for a test process.

  keys are either :duplicate or :unique and must match the value that the registry was started with, i.e.

  `Registry.start_link(keys: :duplicate, name: :some_registry)`

  The with statement handles a couple of cases:
  1.) If the Pid is already registered, update the map
  2.) If update_value/3 fails with error, that means that the wrong process is attempting to update.
  This may be because a test case with the same PID was just killed, the registry hadn't been updated yet,
  and the current process with the same pid (because recycling is good for the earth) tried to access that
  stale entry. So retry!

  """
  @spec register(registry, context, state, keys) :: :ok | {:error, :registry_not_started}
  def register(registry, context, state, :unique) when is_map(state) do
    Process.sleep(@sleep)

    with pid when is_pid(pid) <- Process.whereis(registry),
         {:error, {:already_registered, _}} <- Registry.register(registry, context, state),
         :error <- Registry.update_value(registry, context, &Map.merge(&1, state)) do
      Registry.unregister(registry, context)
      register(registry, context, state, :unique)
    else
      nil -> {:error, :registry_not_started}
      {_, _} -> :ok
      port when is_port(port) -> :ok
    end
  end

  def register(registry, context, state, :duplicate) when is_map(state) do
    case Process.whereis(registry) do
      nil ->
        {:error, :registry_not_started}

      _pid_or_port ->
        Registry.register(registry, context, state)

        :ok
    end
  end

  @doc "List all pids that have registered state for context"
  @spec lookup_pids(registry, context) :: {:ok, [pid]} | {:error, :registry_not_started}
  def lookup_pids(registry, context) do
    case Process.whereis(registry) do
      pid when is_pid(pid) ->
        registry
        |> Registry.lookup(context)
        |> Enum.map(&elem(&1, 0))
        |> then(&{:ok, &1})

      nil ->
        {:error, :registry_not_started}
    end
  end

  @doc "Get state for a pid or any of its ancestors"
  @spec lookup(registry, context) :: result
  def lookup(registry, context) do
    with {:ok, registered_pids} <- lookup_pids(registry, context) do
      ancestors()
      |> List.insert_at(0, self())
      |> Enum.find(&(&1 in registered_pids))
      |> case do
        nil -> lookup(registry, context, self())
        pid -> lookup(registry, context, pid)
      end
    end
  end

  defp ancestors do
    Enum.flat_map([:"$callers", :"$ancestors"], &Process.get(&1, []))
  end

  @doc "Get state for a specific pid"
  @spec lookup(registry, context, pid) :: {:error, :pid_not_registered} | {:ok, state}
  def lookup(registry, context, pid) do
    registry
    |> Registry.lookup(context)
    |> Enum.find(&(elem(&1, 0) === pid))
    |> case do
      nil -> {:error, :pid_not_registered}
      {_pid, state} -> {:ok, state}
    end
  end
end
