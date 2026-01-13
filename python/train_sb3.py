import os
from godot_env import GodotDodgeEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
import numpy as np


class GodotCallback(BaseCallback):
    """Custom callback for logging training progress"""

    def __init__(self, verbose=0, save_freq=50):
        super().__init__(verbose)
        self.episode_rewards = []
        self.episode_lengths = []
        self.best_mean_reward = -np.inf
        self.save_freq = save_freq  # Save checkpoint every N episodes
        self.episode_count = 0

    def _on_step(self):
        # Check if episode ended
        if self.locals.get('dones')[0]:
            info = self.locals.get('infos')[0]
            if 'episode' in info:
                ep_info = info['episode']
                reward = ep_info['r']
                length = ep_info['l']
                time_alive = ep_info['t']

                self.episode_rewards.append(reward)
                self.episode_lengths.append(length)
                self.episode_count += 1

                # Calculate mean over last 100 episodes
                if len(self.episode_rewards) >= 100:
                    mean_reward = np.mean(self.episode_rewards[-100:])

                    # Save best model
                    if mean_reward > self.best_mean_reward:
                        self.best_mean_reward = mean_reward
                        self.model.save('models/best_model')
                        print(f"🎉 New best mean reward: {mean_reward:.2f} - Model saved!")

                # Save periodic checkpoint
                if self.episode_count % self.save_freq == 0:
                    checkpoint_path = f'models/checkpoint_ep{self.episode_count}'
                    self.model.save(checkpoint_path)
                    print(f"💾 Checkpoint saved at episode {self.episode_count}")

                # Print episode stats
                print(f"Episode {self.episode_count} | Time: {time_alive:.2f}s | "
                      f"Reward: {reward:.1f} | Length: {length}")

        return True


def train(total_timesteps=100000, continue_from=None):
    """Train the agent using PPO"""

    # Create environment
    env = GodotDodgeEnv()
    env.connect()

    # Create or load model
    if continue_from and os.path.exists(f"{continue_from}.zip"):
        print(f"Loading model from {continue_from}")
        model = PPO.load(continue_from, env=env)
        print("✓ Model loaded, continuing training...")
    else:
        print("Creating new PPO model...")
        model = PPO(
            "MlpPolicy",
            env,
            learning_rate=3e-4,
            n_steps=2048,
            batch_size=64,
            n_epochs=10,
            gamma=0.99,
            gae_lambda=0.95,
            clip_range=0.2,
            ent_coef=0.01,  # Entropy coefficient for exploration
            verbose=1,
            tensorboard_log="./tensorboard_logs/")

    # Create callback (save checkpoint every 50 episodes)
    callback = GodotCallback(save_freq=100)

    print("\n=== Starting PPO Training ===")
    print(f"Total timesteps: {total_timesteps}")
    print("Press Ctrl+C to stop and save\n")

    try:
        # Train the model
        model.learn(
            total_timesteps=total_timesteps,
            callback=callback,
            progress_bar=True  # Disabled - install stable-baselines3[extra] to enable
        )

        print("\n✓ Training completed!")

    except KeyboardInterrupt:
        print("\n\nTraining interrupted by user")

    finally:
        # Save final model
        model.save('models/final_model')
        print("Final model saved to models/final_model.zip")

        # Print statistics
        if callback.episode_rewards:
            print(f"\nTraining Statistics:")
            print(f"  Episodes completed: {len(callback.episode_rewards)}")
            print(f"  Best mean reward: {callback.best_mean_reward:.2f}")
            print(f"  Final mean reward: {np.mean(callback.episode_rewards[-100:]):.2f}")

        env.close()


if __name__ == "__main__":
    import sys

    # Create models directory
    os.makedirs('models', exist_ok=True)

    # Check if user wants to continue from checkpoint
    if len(sys.argv) > 1:
        checkpoint_path = sys.argv[1]
        train(total_timesteps=100000, continue_from=checkpoint_path)
    else:
        train(total_timesteps=100000)