import socket
import json
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np
from collections import deque
import random


# Simple Neural Network for PPO
class PolicyNetwork(nn.Module):
    def __init__(self, input_size, hidden_size=128):
        super().__init__()

        # Shared layers
        self.shared = nn.Sequential(
            nn.Linear(input_size, hidden_size),
            nn.ReLU(),
            nn.Linear(hidden_size, hidden_size),
            nn.ReLU()
        )

        # Policy head (outputs action)
        self.policy_head = nn.Sequential(
            nn.Linear(hidden_size, 64),
            nn.ReLU(),
            nn.Linear(64, 2)  # Output: [direction_x, direction_y]
        )

        # Dash head (outputs probability to dash)
        self.dash_head = nn.Sequential(
            nn.Linear(hidden_size, 32),
            nn.ReLU(),
            nn.Linear(32, 1),
            nn.Sigmoid()  # 0 to 1 probability
        )

        # Value head (estimates state value)
        self.value_head = nn.Sequential(
            nn.Linear(hidden_size, 64),
            nn.ReLU(),
            nn.Linear(64, 1)
        )

    def forward(self, x):
        shared_features = self.shared(x)

        # Get direction (will be normalized)
        direction = self.policy_head(shared_features)
        direction = torch.tanh(direction)  # Range [-1, 1]

        # Get dash probability
        dash_prob = self.dash_head(shared_features)

        # Get state value
        value = self.value_head(shared_features)

        return direction, dash_prob, value


class GodotEnv:
    def __init__(self, host='127.0.0.1', port=5555):
        self.host = host
        self.port = port
        self.server_socket = None
        self.client_socket = None
        self.buffer = ""

    def start_server(self):
        """Start TCP server and wait for Godot to connect"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(1)

        print(f"Waiting for Godot to connect on {self.host}:{self.port}...")
        self.client_socket, addr = self.server_socket.accept()
        print(f"Connected to Godot at {addr}")

        # Set non-blocking mode for receiving
        self.client_socket.setblocking(False)

    def receive_state(self):
        """Receive state from Godot"""
        try:
            data = self.client_socket.recv(4096).decode('utf-8')
            if not data:
                return None

            self.buffer += data

            # Check if we have a complete message (ends with newline)
            if '\n' in self.buffer:
                message, self.buffer = self.buffer.split('\n', 1)
                return json.loads(message)
        except BlockingIOError:
            # No data available yet
            return None
        except Exception as e:
            print(f"Error receiving state: {e}")
            return None

    def send_action(self, direction, dash):
        """Send action to Godot"""
        action = {
            "direction": direction.tolist() if isinstance(direction, np.ndarray) else direction,
            "dash": bool(dash)
        }

        message = json.dumps(action) + '\n'
        try:
            self.client_socket.sendall(message.encode('utf-8'))
        except Exception as e:
            print(f"Error sending action: {e}")

    def close(self):
        """Close connections"""
        if self.client_socket:
            self.client_socket.close()
        if self.server_socket:
            self.server_socket.close()


def process_state(state_dict):
    """Convert state dictionary to tensor"""
    # Danger grid: 121 values
    danger_grid = state_dict['danger_grid']

    # Player info: 4 values (pos_x, pos_y, vel_x, vel_y)
    player_info = state_dict['player_pos'] + state_dict['player_vel']

    # Normalize player position (assuming 1152x648 screen)
    player_info[0] /= 1152.0
    player_info[1] /= 648.0
    player_info[2] /= 200.0  # MAX_SPEED
    player_info[3] /= 200.0

    # Bullet info: closest 5 bullets, 3 values each (pos_x, pos_y, dist)
    # Pad with zeros if fewer bullets
    bullet_data = []
    for i in range(5):
        if i < len(state_dict['bullets']):
            bullet = state_dict['bullets'][i]
            bullet_data.extend([
                bullet['pos'][0] / 1152.0,
                bullet['pos'][1] / 648.0,
                bullet['dist'] / 500.0  # Normalize distance
            ])
        else:
            bullet_data.extend([0, 0, 0])

    # Can dash: 1 value
    can_dash = [1.0 if state_dict['can_dash'] else 0.0]

    # Combine all features
    features = danger_grid + player_info + bullet_data + can_dash

    return torch.FloatTensor(features)


def train(continue_from=None):
    # Initialize environment
    env = GodotEnv()
    env.start_server()

    # Calculate input size
    # 121 (danger grid) + 4 (player) + 15 (5 bullets * 3) + 1 (can_dash) = 141
    input_size = 141

    # Initialize network
    policy_net = PolicyNetwork(input_size)
    optimizer = optim.Adam(policy_net.parameters(), lr=0.0003)

    # Load checkpoint if specified
    episode_start = 0
    best_time = 0

    if continue_from:
        try:
            checkpoint = torch.load(continue_from)
            policy_net.load_state_dict(checkpoint['model_state'])
            optimizer.load_state_dict(checkpoint['optimizer_state'])
            episode_start = checkpoint['episode']
            best_time = checkpoint['best_time']
            print(f"✓ Loaded checkpoint from episode {episode_start}")
            print(f"  Best time so far: {best_time:.2f}s")
        except FileNotFoundError:
            print(f"✗ Checkpoint not found at {continue_from}")
            print("Starting fresh training...")

    # Training stats
    episode = episode_start
    total_reward = 0

    print("\n=== Starting Training ===")
    print("Press Ctrl+C to stop\n")

    try:
        while True:
            state_dict = env.receive_state()

            if state_dict is None:
                continue

            # DEBUG: Print received state type
            # if episode < 5 or episode % 10 == 0:  # Only print occasionally
            #     print(f"[DEBUG] Received state - Done: {state_dict.get('done', False)}")

            # Check if episode ended
            if state_dict.get('done', False):
                episode += 1
                episode_time = state_dict.get('time_alive', 0)

                if episode_time > best_time:
                    best_time = episode_time
                    # Save best model (simple version)
                    torch.save(policy_net.state_dict(), 'models/best_model.pth')
                    print(f"🎉 New best time: {episode_time:.2f}s - Model saved!")

                # Save checkpoint every 50 episodes
                if episode % 50 == 0:
                    checkpoint = {
                        'model_state': policy_net.state_dict(),
                        'optimizer_state': optimizer.state_dict(),
                        'episode': episode,
                        'best_time': best_time
                    }
                    torch.save(checkpoint, f'models/checkpoint_ep{episode}.pth')
                    print(f"💾 Checkpoint saved at episode {episode}")

                print(f"Episode {episode} | Time: {episode_time:.2f}s | Best: {best_time:.2f}s")
                total_reward = 0
                continue

            # Process state
            state_tensor = process_state(state_dict).unsqueeze(0)  # Add batch dimension

            # Get action from network
            with torch.no_grad():
                direction, dash_prob, value = policy_net(state_tensor)

            # Extract values
            direction = direction.squeeze().numpy()
            dash_prob = dash_prob.item()

            # Add exploration noise (decreases over time)
            epsilon = max(0.1, 1.0 - episode * 0.001)
            if random.random() < epsilon:
                # Random action
                angle = random.random() * 2 * np.pi
                direction = np.array([np.cos(angle), np.sin(angle)])
                dash_prob = random.random()

            # Decide whether to dash
            should_dash = dash_prob > 0.5

            # Send action to Godot
            env.send_action(direction, should_dash)

            # Accumulate reward
            reward = state_dict.get('reward', 0)
            total_reward += reward

    except KeyboardInterrupt:
        print("\n\nTraining stopped by user")
        print(f"Best time achieved: {best_time:.2f}s")
        # Save final checkpoint
        checkpoint = {
            'model_state': policy_net.state_dict(),
            'optimizer_state': optimizer.state_dict(),
            'episode': episode,
            'best_time': best_time
        }
        torch.save(checkpoint, 'models/final_checkpoint.pth')
        print("Final checkpoint saved!")
    finally:
        env.close()
        print("Connections closed")


if __name__ == "__main__":
    import sys

    # Create models directory
    import os

    os.makedirs('models', exist_ok=True)

    # Check if user wants to continue from checkpoint
    if len(sys.argv) > 1:
        checkpoint_path = sys.argv[1]
        train(continue_from=checkpoint_path)
    else:
        train()