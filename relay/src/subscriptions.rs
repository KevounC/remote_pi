use std::collections::{HashMap, HashSet};

/// Shared replacement/subset/removal graph for relay control subscriptions.
///
/// `subscribers_of[target]` answers "who wants updates about this target?".
/// `subscriptions_by[subscriber]` answers "what targets must be cleaned up
/// when this subscriber disconnects?".
#[derive(Debug, Default)]
pub(crate) struct SubscriptionIndex {
    subscribers_of: HashMap<String, HashSet<String>>,
    subscriptions_by: HashMap<String, HashSet<String>>,
}

impl SubscriptionIndex {
    /// Replaces `subscriber`'s full subscription list. An empty list clears all
    /// watched targets and does not leave an empty `subscriptions_by` entry.
    pub fn replace(&mut self, subscriber: String, targets: Vec<String>) {
        self.remove_all(&subscriber);
        let new_set: HashSet<String> = targets.into_iter().collect();
        for target in &new_set {
            self.subscribers_of
                .entry(target.clone())
                .or_default()
                .insert(subscriber.clone());
        }
        if !new_set.is_empty() {
            self.subscriptions_by.insert(subscriber, new_set);
        }
    }

    /// Removes a subset of watched targets for `subscriber`.
    pub fn remove(&mut self, subscriber: &str, targets: Vec<String>) {
        for target in &targets {
            if let Some(set) = self.subscribers_of.get_mut(target) {
                set.remove(subscriber);
            }
            if let Some(subscriptions) = self.subscriptions_by.get_mut(subscriber) {
                subscriptions.remove(target);
            }
        }
        if self
            .subscriptions_by
            .get(subscriber)
            .is_some_and(HashSet::is_empty)
        {
            self.subscriptions_by.remove(subscriber);
        }
    }

    /// Removes every target watched by `subscriber`.
    pub fn remove_all(&mut self, subscriber: &str) {
        if let Some(targets) = self.subscriptions_by.remove(subscriber) {
            for target in &targets {
                if let Some(set) = self.subscribers_of.get_mut(target) {
                    set.remove(subscriber);
                }
            }
        }
    }

    /// Returns all subscribers watching `target`.
    pub fn subscribers_of(&self, target: &str) -> Vec<String> {
        self.subscribers_of
            .get(target)
            .map(|subscribers| subscribers.iter().cloned().collect())
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replace_updates_reverse_edges() {
        let mut index = SubscriptionIndex::default();
        index.replace("B".into(), vec!["A".into(), "C".into()]);
        assert!(index.subscribers_of("A").contains(&"B".to_string()));
        assert!(index.subscribers_of("C").contains(&"B".to_string()));

        index.replace("B".into(), vec!["A".into()]);
        assert!(index.subscribers_of("A").contains(&"B".to_string()));
        assert!(!index.subscribers_of("C").contains(&"B".to_string()));
    }

    #[test]
    fn empty_replace_clears_subscriber_without_empty_entry() {
        let mut index = SubscriptionIndex::default();
        index.replace("B".into(), vec!["A".into()]);
        index.replace("B".into(), vec![]);
        assert!(index.subscribers_of("A").is_empty());
        assert!(!index.subscriptions_by.contains_key("B"));
    }

    #[test]
    fn remove_subset_and_remove_all_cleanup() {
        let mut index = SubscriptionIndex::default();
        index.replace("B".into(), vec!["A".into(), "C".into()]);
        index.remove("B", vec!["A".into()]);
        assert!(index.subscribers_of("A").is_empty());
        assert!(index.subscribers_of("C").contains(&"B".to_string()));

        index.remove_all("B");
        assert!(index.subscribers_of("C").is_empty());
    }
}
