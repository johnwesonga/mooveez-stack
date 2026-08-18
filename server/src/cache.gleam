import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/order
import gleam/otp/actor
import gleam/time/duration
import gleam/time/timestamp

pub type CacheEntry {
  CacheEntry(status: Int, body: String, expires_at: timestamp.Timestamp)
}

pub type CacheMessage {
  Get(key: String, reply_with: Subject(option.Option(CacheEntry)))
  Set(key: String, status: Int, body: String)
}

pub fn start() -> Result(actor.Started(Subject(CacheMessage)), actor.StartError) {
  actor.new(dict.new())
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: dict.Dict(String, CacheEntry),
  cache_message: CacheMessage,
) -> actor.Next(dict.Dict(String, CacheEntry), CacheMessage) {
  case cache_message {
    Get(key, reply_with) -> {
      let entry = case dict.get(state, key) {
        Ok(entry) ->
          case timestamp.compare(timestamp.system_time(), entry.expires_at) {
            order.Lt -> option.Some(entry)
            _ -> option.None
          }
        Error(_) -> option.None
      }
      process.send(reply_with, entry)
      actor.continue(state)
    }

    Set(key, status, body) -> {
      let entry =
        CacheEntry(
          status:,
          body:,
          expires_at: timestamp.add(
            timestamp.system_time(),
            duration.seconds(600),
          ),
        )
      actor.continue(dict.insert(state, key, entry))
    }
  }
}
