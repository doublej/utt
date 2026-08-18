import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { readHistory, toDate } from "./utt";

/** Enough to find the thing you said a moment ago and lost. Beyond that, the app's
 * own history window is the better tool — and rendering all of it here is slow. */
const SHOWN = 100;

export default function Command() {
  const { data, isLoading } = usePromise(async () => (await readHistory()).slice(0, SHOWN));

  return (
    <List isLoading={isLoading} isShowingDetail searchBarPlaceholder="Search transcriptions…">
      <List.EmptyView
        icon={Icon.Text}
        title="Nothing transcribed yet"
        description="Hold utt's hotkey, say something, and it will show up here."
      />
      {(data ?? []).map((transcript) => (
        <List.Item
          key={transcript.id}
          icon={Icon.Text}
          title={transcript.text}
          accessories={[{ date: toDate(transcript.timestamp) }]}
          detail={
            <List.Item.Detail
              markdown={transcript.text}
              metadata={
                <List.Item.Detail.Metadata>
                  <List.Item.Detail.Metadata.Label
                    title="Recorded"
                    text={toDate(transcript.timestamp).toLocaleString()}
                  />
                  <List.Item.Detail.Metadata.Label
                    title="Length"
                    text={`${transcript.duration.toFixed(1)}s`}
                  />
                  {transcript.sourceAppName ? (
                    <List.Item.Detail.Metadata.Label title="Dictated into" text={transcript.sourceAppName} />
                  ) : null}
                </List.Item.Detail.Metadata>
              }
            />
          }
          actions={
            <ActionPanel>
              <Action.Paste content={transcript.text} />
              <Action.CopyToClipboard content={transcript.text} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
