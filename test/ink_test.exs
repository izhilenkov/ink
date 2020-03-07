defmodule InkTest do
  use ExUnit.Case, async: false

  require Logger

  setup do
    {:ok, _} = Logger.add_backend(Ink)
    Logger.configure_backend(Ink, io_device: self())

    on_exit(fn ->
      Logger.flush()
      Logger.remove_backend(Ink)
    end)
  end

  test "it can be configured" do
    Logger.configure_backend(Ink, test: :moep)
  end

  test "it logs a message" do
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}

    assert %{
             "name" => "ink",
             "hostname" => hostname,
             "pid" => pid,
             "msg" => "test",
             "time" => timestamp,
             "level" => 30,
             "v" => 0
           } = Jason.decode!(msg)

    assert is_binary(hostname)
    assert is_integer(pid)

    assert {:ok, _} = NaiveDateTime.from_iso8601(timestamp)
  end

  test "it logs an IO list" do
    Logger.info(["test", ["with", "list"]])

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    decoded_msg = Jason.decode!(msg)
    assert "testwithlist" == decoded_msg["msg"]
  end

  test "it includes an ISO 8601 timestamp" do
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    assert %{"time" => timestamp} = Jason.decode!(msg)
    assert {:ok, _, 0} = DateTime.from_iso8601(timestamp)
    assert timestamp =~ ~r/\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d.\d\d\dZ/
  end

  test "it logs all metadata if not configured" do
    Logger.metadata(not_included: 1, included: 1)
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    decoded_msg = Jason.decode!(msg)
    assert 1 == decoded_msg["not_included"]
    assert 1 == decoded_msg["included"]

    assert "test it logs all metadata if not configured/1" ==
             decoded_msg["function"]
  end

  test "it only includes configured metadata" do
    Logger.configure_backend(Ink, metadata: [:included])
    Logger.metadata(not_included: 1, included: 1)
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    decoded_msg = Jason.decode!(msg)
    assert nil == decoded_msg["not_included"]
    assert 1 == decoded_msg["included"]
  end

  test "it puts the erlang process pid into erlang_pid" do
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    decoded_msg = Jason.decode!(msg)
    assert inspect(self()) == decoded_msg["erlang_pid"]
  end

  test "respects log level" do
    Logger.configure_backend(Ink, level: :warn)
    Logger.info("test")

    refute_receive {:io_request, _, _, {:put_chars, :unicode, _}}
  end

  test "it filters preconfigured secret strings" do
    Logger.info("this is moep")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    assert %{"msg" => "this is [FILTERED]"} = Jason.decode!(msg)
  end

  test "it filters secret strings" do
    Logger.configure_backend(Ink, filtered_strings: ["SECRET", "", nil])
    Logger.info("this is a SECRET string")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}
    assert %{"msg" => "this is a [FILTERED] string"} = Jason.decode!(msg)
  end

  test "it filters URI credentials" do
    Logger.configure_backend(
      Ink,
      filtered_uri_credentials: [
        "amqp://guest:password@rabbitmq:5672",
        "redis://redis:6379/4",
        "",
        "blarg",
        nil
      ]
    )

    Logger.info("the credentials from your URI are guest and password")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}

    assert %{
             "msg" => "the credentials from your URI are guest and [FILTERED]"
           } = Jason.decode!(msg)
  end

  test "it logs default log level without config" do
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}

    assert %{"level" => 30} = Jason.decode!(msg)
  end

  test "it logs default log level with wrong config" do
    Logger.configure_backend(Ink, level_type: :wrong)
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}

    assert %{"level" => 30} = Jason.decode!(msg)
  end

  test "it logs as_is log level" do
    Logger.configure_backend(Ink, level_type: :as_is)
    Logger.info("test")

    assert_receive {:io_request, _, _, {:put_chars, :unicode, msg}}

    assert %{"level" => "info"} = Jason.decode!(msg)
  end
end
