defmodule SandboxRegistryTest do
  use ExUnit.Case, async: true

  @registry :http_sandbox
  @context :context
  @keys :unique
  @state %{state: "http"}
  @sleep 10

  setup_all do
    start_registry()
  end

  describe "&register/4" do
    test "returns error tuple when sandbox is not started" do
      assert {:error, :registry_not_started} =
               SandboxRegistry.register(:other_registry, @context, @state, @keys)
    end

    test "returns :ok when sandbox is started" do
      assert :ok = SandboxRegistry.register(@registry, @context, @state, @keys)
    end
  end

  describe "&lookup_pids/2" do
    test "returns error tuple when sandbox is not started" do
      assert {:error, :registry_not_started} =
               SandboxRegistry.lookup_pids(:other_registry, @context)
    end

    test "returns tuple with :ok and empty list when sandbox is started, but nothing is registered" do
      assert {:ok, []} = SandboxRegistry.lookup_pids(@registry, @context)
    end

    test "returns tuple with :ok and list of registered pids when sandbox is started and pids are registered" do
      SandboxRegistry.register(
        @registry,
        @context,
        @state,
        :duplicate
      )

      assert {:ok, [pid]} = SandboxRegistry.lookup_pids(@registry, @context)
      assert is_pid(pid)
    end
  end

  describe "&lookup/2" do
    test "returns error tuple when sandbox is not started" do
      assert {:error, :registry_not_started} = SandboxRegistry.lookup(:other_registry, @context)
    end

    test "returns :ok and state for a pid" do
      SandboxRegistry.register(
        @registry,
        @context,
        @state,
        :duplicate
      )

      assert {:ok, %{state: "http"}} = SandboxRegistry.lookup(@registry, @context)
    end
  end

  describe "&lookup/3" do
    test "returns error tuple when pid is not registered" do
      assert {:error, :pid_not_registered} = SandboxRegistry.lookup(@registry, @context, self())
    end

    test "returns :ok and state for a specific registered pid" do
      SandboxRegistry.register(
        @registry,
        @context,
        @state,
        :duplicate
      )

      assert {:ok, [pid]} = SandboxRegistry.lookup_pids(@registry, @context)
      assert {:ok, %{state: "http"}} = SandboxRegistry.lookup(@registry, @context, pid)
    end
  end


  defp start_registry(count \\ 0)
  defp start_registry(10), do: {:error, :could_not_start_registry}
  defp start_registry(count) do
    case Registry.start_link(keys: @keys, name: @registry) do
      {:ok, _} -> :ok
      _ ->
        Process.sleep(@sleep)
        start_registry(count + 1)
    end
  end
end
