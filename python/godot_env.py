import socket
import json
import numpy as np
import gymnasium as gym
from gymnasium import spaces


class GodotDodgeEnv(gym.Env):
    """Gymnasium environment wrapper for Godot bullet hell game"""

    def __init__(self, host='127.0.0.1', port=5555):
        super().__init__()

        self.host = host
        self.port = port
        self.server_socket = None
        self.client_socket = None
        self.buffer = ""

        # Define action space: [direction_x, direction_y, dash]
        # direction_x, direction_y: continuous [-1, 1]
        # dash: discrete {0, 1}
        self.action_space = spaces.Box(
            low=np.array([-1.0, -1.0, 0.0]),
            high=np.array([1.0, 1.0, 1.0]),
            dtype=np.float32
        )

        # Define observation space
        # 121 (danger grid) + 4 (player pos/vel) + 15 (5 bullets * 3) + 1 (can_dash) = 141
        self.observation_space = spaces.Box(
            low=-np.inf,
            high=np.inf,
            shape=(141,),
            dtype=np.float32
        )

        self.current_state = None
        self.episode_reward = 0
        self.episode_length = 0

    def connect(self):
        """Start TCP server and wait for Godot to connect"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(1)

        print(f"Waiting for Godot to connect on {self.host}:{self.port}...")
        self.client_socket, addr = self.server_socket.accept()
        print(f"✓ Connected to Godot at {addr}")

        # Set non-blocking mode
        self.client_socket.setblocking(False)

    def reset(self, seed=None, options=None):
        """Reset the environment"""
        super().reset(seed=seed)

        self.episode_reward = 0
        self.episode_length = 0

        # Wait for first state after reset
        state_dict = self._wait_for_state()

        obs = self._process_state(state_dict)
        info = {}

        return obs, info

    def step(self, action):
        """Execute action and return next state"""
        # Send action to Godot
        direction = action[:2]  # First two elements
        dash = action[2] > 0.5  # Third element as boolean

        self._send_action(direction, dash)

        # Wait for next state
        state_dict = self._wait_for_state()

        # Check if episode ended
        done = state_dict.get('done', False)

        # Get reward
        reward = state_dict.get('reward', 0.0)
        self.episode_reward += reward
        self.episode_length += 1

        # Process observation
        obs = self._process_state(state_dict)

        # Truncated is always False (episode ends only on death)
        truncated = False

        # Info
        info = {}
        if done:
            info['episode'] = {
                'r': self.episode_reward,
                'l': self.episode_length,
                't': state_dict.get('time_alive', 0)
            }

        return obs, reward, done, truncated, info

    def _wait_for_state(self):
        """Block until we receive a complete state"""
        import time
        max_wait = 5.0  # 5 second timeout
        start_time = time.time()

        while time.time() - start_time < max_wait:
            state_dict = self._receive_state()
            if state_dict is not None:
                return state_dict
            time.sleep(0.001)  # Small sleep to prevent busy-waiting

        raise TimeoutError("Timed out waiting for state from Godot")

    def _receive_state(self):
        """Receive state from Godot"""
        try:
            data = self.client_socket.recv(4096).decode('utf-8')
            if not data:
                return None

            self.buffer += data

            # Check if we have a complete message
            if '\n' in self.buffer:
                message, self.buffer = self.buffer.split('\n', 1)
                return json.loads(message)
        except BlockingIOError:
            return None
        except Exception as e:
            print(f"Error receiving state: {e}")
            return None

    def _send_action(self, direction, dash):
        """Send action to Godot"""
        action = {
            "direction": [float(direction[0]), float(direction[1])],
            "dash": bool(dash)
        }

        message = json.dumps(action) + '\n'
        try:
            self.client_socket.sendall(message.encode('utf-8'))
        except Exception as e:
            print(f"Error sending action: {e}")

    def _process_state(self, state_dict):
        """Convert state dictionary to observation array"""
        # Danger grid: 121 values
        danger_grid = state_dict.get('danger_grid', [0.0] * 121)

        # Player info: 4 values (pos_x, pos_y, vel_x, vel_y)
        player_pos = state_dict.get('player_pos', [0.0, 0.0])
        player_vel = state_dict.get('player_vel', [0.0, 0.0])

        # Normalize
        player_info = [
            player_pos[0] / 1152.0,
            player_pos[1] / 648.0,
            player_vel[0] / 200.0,
            player_vel[1] / 200.0
        ]

        # Bullet info: 5 bullets * 3 values
        bullets = state_dict.get('bullets', [])
        bullet_data = []
        for i in range(5):
            if i < len(bullets):
                bullet = bullets[i]
                bullet_data.extend([
                    bullet['pos'][0] / 1152.0,
                    bullet['pos'][1] / 648.0,
                    bullet['dist'] / 500.0
                ])
            else:
                bullet_data.extend([0.0, 0.0, 0.0])

        # Can dash: 1 value
        can_dash = [1.0 if state_dict.get('can_dash', False) else 0.0]

        # Combine all features
        features = danger_grid + player_info + bullet_data + can_dash

        return np.array(features, dtype=np.float32)

    def close(self):
        """Close connections"""
        if self.client_socket:
            self.client_socket.close()
        if self.server_socket:
            self.server_socket.close()