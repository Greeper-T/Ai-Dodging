import sys
from godot_env import GodotDodgeEnv
from stable_baselines3 import PPO


def play(model_path='models/best_model'):
    """Run a trained model"""

    # Create environment
    env = GodotDodgeEnv()
    env.connect()

    # Load model
    try:
        model = PPO.load(model_path)
        print(f"✓ Loaded model from {model_path}")
    except FileNotFoundError:
        print(f"✗ Model not found at {model_path}.zip")
        env.close()
        return

    print("\n=== Running Trained Model ===")
    print("Press Ctrl+C to stop\n")

    episode = 0

    try:
        obs, info = env.reset()

        while True:
            # Get action from model (deterministic = no exploration)
            action, _states = model.predict(obs, deterministic=True)

            # Execute action
            obs, reward, done, truncated, info = env.step(action)

            # Check if episode ended
            if done:
                episode += 1
                if 'episode' in info:
                    ep_info = info['episode']
                    print(f"Episode {episode} | Time: {ep_info['t']:.2f}s | "
                          f"Reward: {ep_info['r']:.1f}")

                # Reset for next episode
                obs, info = env.reset()

    except KeyboardInterrupt:
        print("\n\nPlayback stopped by user")

    finally:
        env.close()
        print("Connection closed")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        model_path = sys.argv[1]
    else:
        model_path = 'models/best_model'

    play(model_path)