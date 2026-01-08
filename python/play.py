import socket
import json
import torch
import numpy as np
from train import PolicyNetwork, GodotEnv, process_state


def play(model_path='models/best_model.pth'):
    """Run a trained model without training"""

    # Initialize environment
    env = GodotEnv()
    env.start_server()

    # Initialize network
    input_size = 141
    policy_net = PolicyNetwork(input_size)

    # Load trained weights
    try:
        policy_net.load_state_dict(torch.load(model_path))
        policy_net.eval()  # Set to evaluation mode
        print(f"✓ Loaded model from {model_path}")
    except FileNotFoundError:
        print(f"✗ Model not found at {model_path}")
        print("Starting with random weights...")

    episode = 0

    print("\n=== Running Trained Model ===")
    print("Press Ctrl+C to stop\n")

    try:
        while True:
            state_dict = env.receive_state()

            if state_dict is None:
                continue

            # Check if episode ended
            if state_dict.get('done', False):
                episode += 1
                episode_time = state_dict.get('time_alive', 0)
                print(f"Episode {episode} | Time: {episode_time:.2f}s")
                continue

            # Process state
            state_tensor = process_state(state_dict).unsqueeze(0)

            # Get action from network (NO exploration noise)
            with torch.no_grad():
                direction, dash_prob, value = policy_net(state_tensor)

            # Extract values
            direction = direction.squeeze().numpy()
            dash_prob = dash_prob.item()

            # Decide whether to dash
            should_dash = dash_prob > 0.5

            # Send action to Godot
            env.send_action(direction, should_dash)

    except KeyboardInterrupt:
        print("\n\nPlayback stopped by user")
    finally:
        env.close()
        print("Connections closed")


if __name__ == "__main__":
    import sys

    # Allow specifying model path as argument
    if len(sys.argv) > 1:
        model_path = sys.argv[1]
    else:
        model_path = 'models/best_model.pth'

    play(model_path)