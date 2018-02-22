defmodule RemoteShellExecutorTest do
  use ExUnit.Case
  doctest RemoteShellExecutor

  test "greets the world" do
    assert RemoteShellExecutor.hello() == :world
  end
end
