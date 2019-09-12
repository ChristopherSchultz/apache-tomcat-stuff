package net.christopherschultz.tomcat.realm;

import java.security.SecureRandom;

import org.apache.catalina.CredentialHandler;
import org.mindrot.jbcrypt.BCrypt;

/**
 * A {@link CredentialHandler} that provides support for the BCrypt algorithm.
 *
 * Uses the jBCrypt library from http://www.mindrot.org/projects/jBCrypt/
 */
public class BCryptCredentialHandler implements CredentialHandler {

    public static final int DEFAULT_LOG_ROUNDS = 12;

    private int logRounds = getDefaultLogRounds();
    private final Object randomLock = new Object();
    private volatile SecureRandom random = null;

    /**
     * @return the salt length that will be used when creating a new stored
     * credential for a given input credential.
     */
    public int getLogRounds() {
        return logRounds;
    }

    /**
     * Set the number of rounds will be used when creating a new stored
     * credential for a given input credential.
     *
     * @param logRounds the number of BCrypt rounds to use
     */
    public void setLogRounds(int logRounds) {
        this.logRounds = logRounds;
    }

    @Override
    public boolean matches(String inputCredentials, String storedCredentials) {
        return BCrypt.checkpw(inputCredentials, storedCredentials);
    }

    @Override
    public String mutate(String inputCredentials) {
        return BCrypt.hashpw(inputCredentials,
                             BCrypt.gensalt(getLogRounds(),
                                            getRandom()));
    }

    private SecureRandom getRandom() {
        // Double checked locking. OK since random is volatile.
        if (random == null) {
            synchronized (randomLock) {
                if (random == null) {
                    random = new SecureRandom();
                }
            }
        }
        return random;
    }

    /**
     * @return the default log rounds used BCrypt.
     */
    protected int getDefaultLogRounds() {
        return DEFAULT_LOG_ROUNDS;
    }
}
